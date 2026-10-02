import SwiftData

/// Migration plan for the Squeegee data store.
/// V1 → V2: drops `TrackedWindowRecord` (tracked window state is now in memory only).
public enum SqueegeeMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SqueegeeSchemaV1.self, SqueegeeSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SqueegeeSchemaV1.self, toVersion: SqueegeeSchemaV2.self)]
    }
}
