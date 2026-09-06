#if !targetEnvironment(macCatalyst)
import Shared
import SwiftUI

@available(iOS 27.0, *)
struct RemoteMediaSettingsView: View {
    @ObservedObject var coordinator: RemoteMediaCoordinator
    @State private var selectedEntity: HAAppEntity?

    init(coordinator: RemoteMediaCoordinator? = nil) { self.coordinator = coordinator ?? .shared }

    var body: some View {
        List {
            Section {
                EntityPicker(
                    selectedServerId: coordinator.selection?.serverId,
                    selectedEntity: $selectedEntity,
                    domainFilter: [.mediaPlayer]
                )
                .accessibilityLabel(L10n.RemoteMedia.follow)
            } header: {
                Text(L10n.RemoteMedia.follow)
            } footer: {
                Text(L10n.RemoteMedia.description)
            }
            if let selection = coordinator.selection {
                Section {
                    LabeledContent(L10n.RemoteMedia.following) {
                        Text(coordinator.snapshot?.deviceName ?? selection.entityId)
                    }
                    // Which server it came from only says something when there is more than one,
                    // the same rule the entity picker uses for its own server filter.
                    if Current.servers.all.count > 1 {
                        LabeledContent(L10n.Settings.ServerSelect.title) {
                            Text(
                                Current.servers.server(forServerIdentifier: selection.serverId)?.info.name
                                    ?? selection.serverId
                            )
                        }
                    }
                    if coordinator.snapshot?.isActive != true {
                        Text(L10n.RemoteMedia.waiting)
                            .foregroundStyle(.secondary)
                    }
                    Button(L10n.RemoteMedia.stopFollowing, role: .destructive) {
                        selectedEntity = nil
                        coordinator.follow(nil)
                    }
                }
            }
            if let error = coordinator.error {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button(L10n.RemoteMedia.retry) { coordinator.refresh() }
                }
            }
            Section {
                Text(L10n.RemoteMedia.foregroundLimitation)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n.RemoteMedia.title)
        .onChange(of: selectedEntity) { entity in
            guard let entity else { return }
            coordinator.follow(.init(serverId: entity.serverId, entityId: entity.entityId))
        }
    }
}

@available(iOS 27.0, *)
extension RemoteMediaSettingsView: SettingsScreenSearchable {
    static var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(L10n.RemoteMedia.follow),
            SettingsSearchEntry(L10n.RemoteMedia.following),
            SettingsSearchEntry(L10n.RemoteMedia.stopFollowing),
        ]
    }
}

@available(iOS 27.0, *)
#Preview {
    NavigationStack { RemoteMediaSettingsView() }
}
#endif
