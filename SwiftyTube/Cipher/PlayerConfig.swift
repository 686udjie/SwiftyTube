//
//  PlayerConfig.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation

public struct PlayerConfig: Codable, Sendable, Equatable {
    public var sig: String?
    public var nClass: String?
    public var sts: Int?
    public var aliases: [String]?

    public init(sig: String? = nil, nClass: String? = nil, sts: Int? = nil, aliases: [String]? = nil) {
        self.sig = sig
        self.nClass = nClass
        self.sts = sts
        self.aliases = aliases
    }

    public var sigFunction: ExtractedFunction {
        ExtractedFunction(body: sig, varName: nil)
    }

    public var nFunction: ExtractedFunction {
        ExtractedFunction(body: nil, varName: nClass)
    }

    /// n-transform IIFE built from nClass.
    public var nJsExpression: String? {
        guard let nClass = nClass else { return nil }
        return "(function(n){try{var u=new g.\(nClass)('https://x.googlevideo.com/videoplayback?n='+n,true);" +
            "var t=u.get('n');return(t&&t!==n)?t:n;}catch(e){return n;}})(INPUT)"
    }
}

public struct ExtractedFunction: Codable, Sendable, Equatable {
    public var body: String?
    public var extractPattern: String?
    public var varName: String?

    public init(body: String? = nil, extractPattern: String? = nil, varName: String? = nil) {
        self.body = body
        self.extractPattern = extractPattern
        self.varName = varName
    }
}
