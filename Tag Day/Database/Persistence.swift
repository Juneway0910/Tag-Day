//
//  Persistence.swift
//  Tag Day
//
//  Created by Ci Zi on 2025/4/29.
//

import Foundation
import GRDB

extension AppDatabase {
    static let shared = makeShared()
    
    private static func makeShared() -> AppDatabase {
        do {
            let databasePool = try generateDatabasePool()
            
            // Create the AppDatabase
            let database = try AppDatabase(databasePool)
            
            return database
        } catch {
            fatalError("Unresolved error \(error)")
        }
    }
    
    static func generateDatabasePool() throws -> DatabasePool {
        let folderURL = try databaseFolderURL()
        try FileManager().createDirectory(at: folderURL, withIntermediateDirectories: true)
        
        let dbURL = folderURL.appendingPathComponent("db.sqlite")
        var config = Configuration()
        config.automaticMemoryManagement = true
        let dbPool = try DatabasePool(path: dbURL.path, configuration: config)
        return dbPool
    }
    
    static func databaseFolderURL() throws -> URL {
        return try FileManager()
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("database", isDirectory: true)
    }
}
