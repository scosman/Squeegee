import SwiftData

/// Migration plan for the WindowCleaner data store. Currently has only V1 with
/// no migrations. New schema versions will add lightweight or custom migration
/// stages here.
public enum WindowCleanerMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [WindowCleanerSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
