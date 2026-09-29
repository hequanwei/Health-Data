//
//  HealthInsightPersistence.swift
//  Health Data
//

import Foundation
import WidgetKit

enum HealthInsightPersistence {
    private static let insightKey = "persisted_health_insight"

    static func save(_ insight: HealthInsightResult) {
        guard let data = try? JSONEncoder().encode(insight) else { return }
        UserDefaults.standard.set(data, forKey: insightKey)
        WidgetSnapshotStore.save(from: insight)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> HealthInsightResult? {
        guard let data = UserDefaults.standard.data(forKey: insightKey),
              let insight = try? JSONDecoder().decode(HealthInsightResult.self, from: data) else {
            return nil
        }
        return insight
    }
}
