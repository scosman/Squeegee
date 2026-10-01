import SwiftData

/// Migration plan for the Squeegee data store. Currently has only V1 with
/// no migrations. New schema versions will add lightweight or custom migration
/// stages here.
public enum SqueegeeMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SqueegeeSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
