import Foundation

enum InstagramScripts {
    static let version = "2026.10.07.1"
    static let messageHandler = "lessPolicy"

    static let openProfile = #"""
    (() => {
        const links = [...document.querySelectorAll('a[href]')];
        const profile = links.find(link => {
            const label = `${link.getAttribute('aria-label') || ''} ${link.textContent || ''}`.trim();
            return /^profile$/i.test(label);
        });
        if (profile) profile.click();
    })();
    """#

    static let bootstrap = #"""
    (() => {
        if (window.lessApp) return;

        const handler = window.webkit?.messageHandlers?.lessPolicy;
        let configuration = { blockReels: true, exitOnScroll: true };
        let authorizedReel = null;
        let touchStartY = null;
        let lastPath = location.pathname;

        const post = (type, details = {}) => handler?.postMessage({ type, ...details });
        const normalizeReel = path => {
            const match = path?.match(/^\/reel\/([^/]+)/i);
            return match ? `/reel/${match[1]}/` : null;
        };
        const isDirect = path => /^\/direct(?:\/|$)/i.test(path);
        const isReelsFeed = path => /^\/reels(?:\/|$)/i.test(path);

        const installStyle = () => {
            let style = document.getElementById('less-policy-style');
            if (!style) {
                style = document.createElement('style');
                style.id = 'less-policy-style';
                (document.head || document.documentElement).appendChild(style);
            }
            const desiredCSS = `
                [data-less-instagram-navigation="true"] {
                    display: none !important;
                }
            ` + (configuration.blockReels ? `
                a[href="/reels/"], a[href^="/reels/"],
                a[href="/reels"], [data-less-reels-entry="true"] {
                    display: none !important;
                }
            ` : '');
            if (style.textContent !== desiredCSS) {
                style.textContent = desiredCSS;
            }
        };

        const markSemanticReelsEntries = () => {
            const navigationLinks = [];
            for (const link of document.querySelectorAll('a[href]')) {
                const href = link.getAttribute('href') || '';
                const label = `${link.getAttribute('aria-label') || ''} ${link.textContent || ''}`.trim();
                const isReelsNavigation = isReelsFeed(href) || (/^reels$/i.test(label) && !normalizeReel(href));
                if (isReelsNavigation) {
                    link.dataset.lessReelsEntry = 'true';
                }

                if (href === '/' || /^\/(explore|direct|reels)(?:\/|$)/i.test(href) || /^profile$/i.test(label)) {
                    navigationLinks.push(link);
                }

                if (/^profile$/i.test(label) && /^\/[A-Za-z0-9._]+\/?$/.test(href)) {
                    post('profilePath', { path: href });
                }
            }

            for (const link of navigationLinks) {
                let candidate = link.parentElement;
                for (let depth = 0; candidate && depth < 16; depth += 1, candidate = candidate.parentElement) {
                    const destinations = new Set();
                    for (const item of candidate.querySelectorAll('a[href]')) {
                        const href = item.getAttribute('href') || '';
                        const label = `${item.getAttribute('aria-label') || ''} ${item.textContent || ''}`.trim();
                        if (href === '/') destinations.add('home');
                        else if (/^\/explore(?:\/|$)/i.test(href)) destinations.add('search');
                        else if (/^\/direct(?:\/|$)/i.test(href)) destinations.add('direct');
                        else if (/^\/reels(?:\/|$)/i.test(href)) destinations.add('reels');
                        else if (/^profile$/i.test(label)) destinations.add('profile');
                    }

                    const bounds = candidate.getBoundingClientRect();
                    const navigationShape = bounds.height < 180 || bounds.width < 140;
                    if (destinations.size >= 3 && navigationShape) {
                        candidate.dataset.lessInstagramNavigation = 'true';
                        return;
                    }
                }
            }
        };

        const enforceRoute = () => {
            const path = location.pathname;
            const reel = normalizeReel(path);

            if (configuration.blockReels && isReelsFeed(path)) {
                post('blockedReel', { path });
            } else if (configuration.blockReels && reel && reel !== authorizedReel) {
                post('blockedReel', { path: reel });
            } else if (!reel) {
                authorizedReel = null;
            }

            lastPath = path;
            installStyle();
            markSemanticReelsEntries();
        };

        document.addEventListener('click', event => {
            const link = event.target?.closest?.('a[href]');
            if (!link) return;

            const href = new URL(link.href, location.href);
            const reel = normalizeReel(href.pathname);

            if (configuration.blockReels && reel) {
                if (isDirect(location.pathname)) {
                    authorizedReel = reel;
                    post('dmReelTapped', { path: reel });
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

        document.addEventListener('touchstart', event => {
            touchStartY = normalizeReel(location.pathname) ? event.touches[0]?.clientY : null;
        }, { passive: true, capture: true });

        document.addEventListener('touchmove', event => {
            if (!configuration.blockReels || !configuration.exitOnScroll || touchStartY === null) return;
            const currentY = event.touches[0]?.clientY;
            if (typeof currentY === 'number' && Math.abs(currentY - touchStartY) > 44) {
                touchStartY = null;
                post('reelAdvanceAttempt');
            }
        }, { passive: true, capture: true });

        document.addEventListener('wheel', event => {
            if (configuration.blockReels && configuration.exitOnScroll && normalizeReel(location.pathname) && Math.abs(event.deltaY) > 20) {
                post('reelAdvanceAttempt');
            }
        }, { passive: true, capture: true });

        document.addEventListener('keydown', event => {
            if (configuration.blockReels && configuration.exitOnScroll && normalizeReel(location.pathname)
                && ['ArrowDown', 'ArrowUp', 'PageDown', 'PageUp'].includes(event.key)) {
                post('reelAdvanceAttempt');
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
        new MutationObserver(() => {
            if (location.pathname !== lastPath) enforceRoute();
            else {
                installStyle();
                markSemanticReelsEntries();
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
