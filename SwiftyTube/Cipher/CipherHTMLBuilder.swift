//
//  CipherHTMLBuilder.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

public enum CipherHTMLBuilder {

    /// Patched player.js with window exports for the WebView.
    public static func patchPlayerJs(
        playerJs: String,
        sigConfig: String?,
        sigIsExpression: Bool = true,
        nClass: String?,
        nJsExpression: String?,
        rawNFuncBody: String? = nil,
        playerHash: String?
    ) -> String {
        var exports: [String] = []

        if let config = sigConfig {
            if sigIsExpression {
                let sigExpr = config.replacingOccurrences(of: "INPUT", with: "sig")
                exports.append(
                    "window._cipherSigFunc=function(sig){try{return \(sigExpr)}catch(e){return null}}"
                )
            } else {
                // config is a raw function declaration - export directly
                exports.append(
                    "window._cipherSigFunc=\(config)"
                )
            }
        }

        // URL builder mimicking YouTube's `s2` (tries classes, alr=yes, sig, then yq/toString/url/clone).
        let nc = "\"\(nClass ?? "lq")\""
        let knownClasses: [String]
        switch nClass {
        case "lq": knownClasses = [nc, "\"WM\""]
        case "WM": knownClasses = [nc, "\"lq\""]
        default:   knownClasses = [nc, "\"WM\"", "\"lq\""]
        }
        let urlBuilderSig: String
        if let config = sigConfig, sigIsExpression {
            urlBuilderSig = config.replacingOccurrences(of: "INPUT", with: "d")
        } else if sigConfig != nil {
            urlBuilderSig = "(window._cipherSigFunc?window._cipherSigFunc(d):d)"
        } else {
            urlBuilderSig = "d"
        }
        let urlBuilder = "window._buildSignedUrl=function(url,sp,sig){try{" +
            "var classes=[" + knownClasses.joined(separator: ",") + "];" +
            "for(var i=0;i<classes.length;i++){try{" +
            "var u=new g[classes[i]](url,true);u.set(\"alr\",\"yes\");" +
            "if(sig){try{var d;try{d=decodeURIComponent(sig)}catch(e){d=sig};" +
            "u.set(sp,\(urlBuilderSig))}catch(e){}}" +
            "var s;" +
            "if(typeof u.yq==='function'){s=u.yq()}" +
            "else if(typeof u.toString==='function'){s=u.toString();if(s==='[object Object]')s=null}" +
            "if(!s&&u.url!==undefined){s=u.url}" +
            "if(!s&&typeof u.clone==='function'){try{s=u.clone()}catch(e){}}" +
            "if(s)return s}catch(e){}}" +
            "return null}catch(e){return null}}"
        exports.append(urlBuilder)

        // n-transform via a dummy ?n= URL read back through the builder class.
        if let nExpr = nJsExpression {
            let expr = nExpr.replacingOccurrences(of: "INPUT", with: "n")
            exports.append("window._nTransformFunc=function(n){try{return \(expr)}catch(e){return n}}")
        } else if let rawBody = rawNFuncBody {
            exports.append("window._nTransformFunc=\(rawBody)")
        }

        // Expose metadata for discovery
        exports.append("window._exportedCipher={sigFuncName:'\(sigConfig ?? "?")',nFuncClass:'\(nClass ?? "?")'}")

        let marker = "})(_yt_player);"
        let exportCode = exports.isEmpty ? "" : "; " + exports.joined(separator: "; ")

        if playerJs.contains(marker) {
            return playerJs.replacingOccurrences(
                of: marker,
                with: "\(exportCode) \(marker)"
            )
        }

        return playerJs + "\n" + exportCode
    }

    /// HTML loading patched player.js plus sig/n/url bridges.
    public static func buildFileBasedHTML(playerHash: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <script src="base_\(playerHash).js"></script>
        <script>
        "use strict";

        // ============================================================
        // SIGNATURE DEOBFUSCATION
        // ============================================================
        function deobfuscateSig(funcName, constantArg, obfuscatedSig) {
            var func = window._cipherSigFunc;
            if (typeof func !== 'function') return null;
            try {
                var r = func(decodeURIComponent(obfuscatedSig));
                return (r !== undefined && r !== null && r !== '') ? String(r) : null;
            } catch(e) {
                return null;
            }
        }

        // ============================================================
        // N-PARAMETER TRANSFORM
        // ============================================================
        function transformN(nValue) {
            var func = window._nTransformFunc;
            if (typeof func !== 'function') return nValue;
            try {
                var result = func(nValue);
                if (result === undefined || result === null || result === '') return nValue;
                var resultStr = String(result);
                return (resultStr.length > 0) ? resultStr : nValue;
            } catch(e) {
                return nValue;
            }
        }

        // ============================================================
        // FULL URL BUILDER - uses player's own URL builder class to
        // construct URL identical to YouTube's s2 function.
        // Pass baseUrl (decoded), sp param name, and URL-encoded sig.
        // Returns the fully constructed URL string.
        // ============================================================
        function buildSignedUrl(baseUrl, sp, encodedSig) {
            if (typeof window._buildSignedUrl === 'function') {
                return window._buildSignedUrl(baseUrl, sp, encodedSig);
            }
            return null;
        }

        // ============================================================
        // READY SIGNAL - validate the exported n-transform first
        // (ported from zemer-cipher): a transform that throws or returns
        // same-value/garbage output must be disabled so the native side
        // strips the untransformed n-param instead of shipping a bad one.
        // ============================================================
        var hasTransformN = typeof window._nTransformFunc === 'function';
        var discoveryInfo = 'n_transform=' + hasTransformN;
        if (hasTransformN) {
            var testInput = "KdrqFlzJXl9EcCwlmEy";
            try {
                var testResult = window._nTransformFunc(testInput);
                var valid = typeof testResult === 'string' &&
                    testResult !== testInput &&
                    testResult.length >= 5 &&
                    /^[a-zA-Z0-9_-]+$/.test(testResult);
                if (!valid) {
                    window._nTransformFunc = null;
                    hasTransformN = false;
                    discoveryInfo = 'n_transform_invalid:' + String(testResult).substring(0, 20);
                }
            } catch(e) {
                window._nTransformFunc = null;
                hasTransformN = false;
                discoveryInfo = 'n_transform_threw:' + e;
            }
        }

        var info = {
            type: 'discovery',
            sigFuncName: typeof _cipherSigFunc === 'function' ? 'exported_sig' : 'NOT_FOUND',
            nFuncName: hasTransformN ? 'exported_n' : 'noop',
            info: discoveryInfo
        };
        window.webkit.messageHandlers.cipher.postMessage(
            JSON.stringify(info)
        );
        window.webkit.messageHandlers.cipher.postMessage(
            JSON.stringify({type:'ready'})
        );
        </script>
        </head><body></body></html>
        """
    }

    // MARK: - Inline HTML (legacy)

    public static func buildHTML(
        playerJs: String,
        sigConfig: String?,
        sigIsExpression: Bool = true,
        nClass: String?,
        nJsExpression: String?,
        rawNFuncBody: String? = nil,
        playerHash: String?
    ) -> String {
        let modifiedJs = patchPlayerJs(
            playerJs: playerJs,
            sigConfig: sigConfig,
            sigIsExpression: sigIsExpression,
            nClass: nClass,
            nJsExpression: nJsExpression,
            rawNFuncBody: rawNFuncBody,
            playerHash: playerHash
        )
        return buildDiscoveryHtml(playerJs: modifiedJs)
    }

    private static func buildDiscoveryHtml(playerJs: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><script>
        "use strict";

        function deobfuscateSig(funcName, constantArg, obfuscatedSig) {
            var func = window._cipherSigFunc;
            if (typeof func !== 'function') return null;
            try {
                var r = func(decodeURIComponent(obfuscatedSig));
                return (r !== undefined && r !== null && r !== '') ? String(r) : null;
            } catch(e) {
                return null;
            }
        }

        function transformN(nValue) {
            var func = window._nTransformFunc;
            if (typeof func !== 'function') return nValue;
            try {
                var result = func(nValue);
                if (result === undefined || result === null || result === '') return nValue;
                var resultStr = String(result);
                return (resultStr.length > 0) ? resultStr : nValue;
            } catch(e) {
                return nValue;
            }
        }

        function buildSignedUrl(baseUrl, sp, encodedSig) {
            if (typeof window._buildSignedUrl === 'function') {
                return window._buildSignedUrl(baseUrl, sp, encodedSig);
            }
            return null;
        }

        function discoverAndInit() {
            var nFuncName = "";
            var sigFuncName = typeof _cipherSigFunc === 'function' ? 'exported_fJ' : 'NOT_FOUND';
            var info = 'player_inline';

            if (typeof window._nTransformFunc === 'function') {
                try {
                    var testInput = "KdrqFlzJXl9EcCwlmEy";
                    var testResult = window._nTransformFunc(testInput);
                    if (typeof testResult === 'string' && testResult !== testInput && /^[a-zA-Z0-9_-]+$/.test(testResult)) {
                        nFuncName = "exported_n_func";
                        info = "n_transform_active";
                    }
                } catch(e) {}
            }

            window.webkit.messageHandlers.cipher.postMessage(
                JSON.stringify({type:'discovery',sigFuncName:sigFuncName,nFuncName:nFuncName,info:info})
            );
            window.webkit.messageHandlers.cipher.postMessage(
                JSON.stringify({type:'ready'})
            );
        }
        </script>
        <script>
        \(playerJs)
        </script>
        <script>
        discoverAndInit();
        </script>
        </head><body></body></html>
        """
    }
}
