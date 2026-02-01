//
//  SupabaseConfig.swift
//  MOMENTA
//
//  Supabase 基础配置
//

import Foundation
import Supabase

enum SupabaseConfig {
    static let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? "https://your-project-id.supabase.co"
    static let url: URL = {
        #if DEBUG
        print("ℹ️ [DEBUG] Supabase URL: \(urlString)")
        #endif
        return URL(string: urlString) ?? URL(string: "https://placeholder.com")!
    }()
    
    static let anonKey: String = {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? "your-anon-key"
        #if DEBUG
        if key == "your-anon-key" || key.isEmpty { print("⚠️ [DEBUG] Supabase Anon Key is missing or default!") }
        #endif
        return key
    }()
    
    static let client = SupabaseClient(
        supabaseURL: url,
        supabaseKey: anonKey,
        options: SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(
                emitLocalSessionAsInitialSession: true
            )
        )
    )
}
