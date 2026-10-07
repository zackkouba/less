import Foundation

enum InstagramScripts {
    static let version = "2026.10.07.20"
    static let messageHandler = "lessPolicy"

    static let bootstrap = #"""
    (() => {
        if (window.lessApp) return;

        const handler = window.webkit?.messageHandlers?.lessPolicy;
        let configuration = { blockReels: true, exitOnScroll: true };
        let authorizedReel = null;
        let isAwaitingAuthorizedReel = false;
        let authorizationTimeout = null;
        let dmContentPath = null;
        let lastObservedContentPath = null;
        let hasEnteredDMContent = false;
        let lastPath = location.pathname;
        let lastBackgroundColor = null;
        let lastActiveVideoSignature = null;
        let hasObservedDMVideo = false;
        let videoInspectionTimer = null;
        let videoSessionEndTimer = null;
        let nextVideoElementID = 1;
        const videoElementIDs = new WeakMap();

        const post = (type, details = {}) => handler?.postMessage({ type, ...details });
        const compactLogValue = value => value.length > 50
            ? `${value.slice(0, 50)}…`
            : value;
        const normalizeReel = path => {
            const match = path?.match(/^\/reel\/([^/]+)/i);
            return match ? `/reel/${match[1]}/` : null;
        };
        const normalizeContent = path => {
            const match = path?.match(/^\/(p|reel|reels)\/([^/]+)\/?/i);
            return match ? `/${match[1].toLowerCase()}/${match[2]}/` : null;
        };
        const isDirect = path => /^\/direct(?:\/|$)/i.test(path);
        const isReelsFeed = path => /^\/reels\/?$/i.test(path);
        const videoElementID = video => {
            if (!videoElementIDs.has(video)) {
                videoElementIDs.set(video, nextVideoElementID);
                nextVideoElementID += 1;
            }
            return videoElementIDs.get(video);
        };
        const visibleVideoArea = video => {
            const rect = video.getBoundingClientRect();
            const width = Math.max(0, Math.min(rect.right, innerWidth) - Math.max(rect.left, 0));
            const height = Math.max(0, Math.min(rect.bottom, innerHeight) - Math.max(rect.top, 0));
            return width * height;
        };
        const videoSignature = video => {
            const nearbyLink = video.closest('a[href]')
                || video.parentElement?.closest?.('a[href]');
            const linkedContent = nearbyLink
                ? normalizeContent(new URL(nearbyLink.href, location.href).pathname)
                : null;
            const mediaSource = video.currentSrc
                || video.src
                || video.querySelector('source[src]')?.src
                || video.poster;
            if (!linkedContent && !mediaSource) return null;
            return `${videoElementID(video)}|${linkedContent || mediaSource}`;
        };
        const endVideoSession = () => {
            dmContentPath = null;
            lastObservedContentPath = null;
            hasEnteredDMContent = false;
            lastActiveVideoSignature = null;
            hasObservedDMVideo = false;
            post('dmVideoSessionEnded');
        };
        const inspectActiveVideo = () => {
            videoInspectionTimer = null;
            if (!dmContentPath && !isDirect(location.pathname)) return;

            const candidates = [...document.querySelectorAll('video')]
                .map(video => ({ video, area: visibleVideoArea(video) }))
                .filter(candidate => candidate.area >= innerWidth * innerHeight * 0.2)
                .sort((first, second) => second.area - first.area);
            const activeVideo = candidates.find(candidate => !candidate.video.paused)?.video
                || candidates[0]?.video;

            if (!activeVideo) {
                if (hasObservedDMVideo && !videoSessionEndTimer) {
                    videoSessionEndTimer = setTimeout(endVideoSession, 1500);
                }
                return;
            }

            clearTimeout(videoSessionEndTimer);
            videoSessionEndTimer = null;
            const signature = videoSignature(activeVideo);
            if (!signature) return;

            if (!dmContentPath) {
                dmContentPath = "dom-video-session";
                lastObservedContentPath = null;
                hasEnteredDMContent = true;
                console.log('[Less] Started DM video session from visible video', compactLogValue(signature));
                post('dmVideoSessionStarted', { value: signature });
            }

            if (!lastActiveVideoSignature) {
                lastActiveVideoSignature = signature;
                hasObservedDMVideo = true;
                console.log('[Less] Tracking first active DM video', compactLogValue(signature));
                post('dmVideoObserved', { value: signature });
            } else if (signature !== lastActiveVideoSignature) {
                const previous = lastActiveVideoSignature;
                lastActiveVideoSignature = signature;
                console.log('[Less] Detected active video transition after DM', {
                    from: compactLogValue(previous),
                    to: compactLogValue(signature)
                });
                post('dmVideoTransition', { from: previous, to: signature });
            }
        };
        const scheduleVideoInspection = () => {
            if (videoInspectionTimer) return;
            videoInspectionTimer = setTimeout(inspectActiveVideo, 250);
        };
        const reportBackgroundColor = () => {
            const transparent = color => !color || color === 'rgba(0, 0, 0, 0)';
            let sampledElement = document.elementFromPoint(
                Math.round(innerWidth / 2),
                Math.max(0, innerHeight - 2)
            );
            let sampledColor = '';
            while (sampledElement && transparent(sampledColor)) {
                sampledColor = getComputedStyle(sampledElement).backgroundColor;
                sampledElement = sampledElement.parentElement;
            }

            const bodyColor = document.body ? getComputedStyle(document.body).backgroundColor : '';
            const rootColor = getComputedStyle(document.documentElement).backgroundColor;
            const color = !transparent(sampledColor)
                ? sampledColor
                : (!transparent(bodyColor) ? bodyColor : rootColor);
            if (color && color !== 'rgba(0, 0, 0, 0)' && color !== lastBackgroundColor) {
                lastBackgroundColor = color;
                post('pageBackgroundColor', { value: color });
            }
        };

        const installStyle = () => {
            let style = document.getElementById('less-policy-style');
            if (!style) {
                style = document.createElement('style');
                style.id = 'less-policy-style';
                (document.head || document.documentElement).appendChild(style);
            }
            const desiredCSS = configuration.blockReels ? `
                a[href="/reels/"], a[href^="/reels/"],
                a[href="/reels"], [data-less-reels-entry="true"] {
                    display: none !important;
                }
            ` : '';
            if (style.textContent !== desiredCSS) {
                style.textContent = desiredCSS;
            }
        };

        const markSemanticReelsEntries = () => {
            for (const link of document.querySelectorAll('a[href]')) {
                const href = link.getAttribute('href') || '';
                const label = `${link.getAttribute('aria-label') || ''} ${link.textContent || ''}`.trim();
                const isReelsNavigation = isReelsFeed(href) || (/^reels$/i.test(label) && !normalizeReel(href));
                if (isReelsNavigation) {
                    link.dataset.lessReelsEntry = 'true';
                }

            }
        };

        const enforceRoute = () => {
            const path = location.pathname;
            const reel = normalizeReel(path);
            const contentPath = normalizeContent(path);

            if (dmContentPath && contentPath) {
                hasEnteredDMContent = true;
                if (lastObservedContentPath && contentPath !== lastObservedContentPath) {
                    console.log('[Less] Detected content transition after DM', {
                        from: lastObservedContentPath,
                        to: contentPath
                    });
                    post('dmContentTransition', {
                        from: lastObservedContentPath,
                        to: contentPath
                    });
                }
                lastObservedContentPath = contentPath;
            } else if (dmContentPath
                && dmContentPath !== "dom-video-session"
                && hasEnteredDMContent
                && !contentPath) {
                dmContentPath = null;
                lastObservedContentPath = null;
                hasEnteredDMContent = false;
                post('dmContentSessionEnded');
            }

            if (configuration.blockReels && isReelsFeed(path)) {
                post('blockedReel', { path });
            } else if (configuration.blockReels && reel && reel !== authorizedReel && !dmContentPath) {
                post('blockedReel', { path: reel });
            } else if (reel && reel === authorizedReel) {
                isAwaitingAuthorizedReel = false;
                clearTimeout(authorizationTimeout);
                authorizationTimeout = null;
            } else if (!reel) {
                if (!isAwaitingAuthorizedReel) authorizedReel = null;
            }

            lastPath = path;
            installStyle();
            markSemanticReelsEntries();
            reportBackgroundColor();
        };

        document.addEventListener('click', event => {
            const link = event.target?.closest?.('a[href]');
            if (!link) return;

            const href = new URL(link.href, location.href);
            const reel = normalizeReel(href.pathname);
            const contentPath = normalizeContent(href.pathname);

            if (isDirect(location.pathname) && contentPath) {
                dmContentPath = contentPath;
                lastObservedContentPath = contentPath;
                hasEnteredDMContent = false;
                lastActiveVideoSignature = null;
                hasObservedDMVideo = false;
                clearTimeout(videoSessionEndTimer);
                videoSessionEndTimer = null;
                scheduleVideoInspection();
                console.log('[Less] Tracking content opened from DM', { path: contentPath });
                post('dmContentTapped', {
                    path: contentPath,
                    returnPath: `${location.pathname}${location.search}`
                });
            }

            if (configuration.blockReels && reel) {
                if (isDirect(location.pathname)) {
                    authorizedReel = reel;
                    isAwaitingAuthorizedReel = true;
                    clearTimeout(authorizationTimeout);
                    authorizationTimeout = setTimeout(() => {
                        if (!normalizeReel(location.pathname)) {
                            authorizedReel = null;
                            isAwaitingAuthorizedReel = false;
                        }
                    }, 3000);
                    post('dmReelTapped', {
                        path: reel,
                        returnPath: `${location.pathname}${location.search}`
                    });
                } else if (reel !== authorizedReel) {
                    event.preventDefault();
                    event.stopImmediatePropagation();
                    post('blockedReel', { path: reel });
                }
            } else if (configuration.blockReels && isReelsFeed(href.pathname)) {
                event.preventDefault();
                event.stopImmediatePropagation();
                post('blockedReel', { path: href.pathname });
            }
        }, true);

        for (const method of ['pushState', 'replaceState']) {
            const original = history[method];
            history[method] = function(...argumentsList) {
                const result = original.apply(this, argumentsList);
                queueMicrotask(enforceRoute);
                return result;
            };
        }

        addEventListener('popstate', enforceRoute);
        document.addEventListener('play', scheduleVideoInspection, true);
        document.addEventListener('loadedmetadata', scheduleVideoInspection, true);
        setInterval(scheduleVideoInspection, 500);
        new MutationObserver(() => {
            scheduleVideoInspection();
            if (location.pathname !== lastPath) enforceRoute();
            else {
                installStyle();
                markSemanticReelsEntries();
                reportBackgroundColor();
            }
        }).observe(document.documentElement, { childList: true, subtree: true });

        window.lessApp = {
            configure(options) {
                configuration = { ...configuration, ...options };
                if (!configuration.blockReels) authorizedReel = null;
                enforceRoute();
            },
            setAppearance(value) {
                document.documentElement.style.colorScheme = value;
            }
        };

        enforceRoute();
    })();
    """#
}
