import SwiftUI
import ObjCBridgeKit

public struct ExportDemoView: View {
    @State private var viewModel = ExportDemoViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        viewModel.runBatch(count: 8)
                    } label: {
                        HStack {
                            Text("Run Export Batch")
                            if viewModel.isRunning {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.isRunning)
                } footer: {
                    Text("Fires 8 concurrent legacy delegate callbacks through the Swift 6 gateway. One in five is forced to fail, on purpose.")
                }

                Section("Completed (\(viewModel.completedPaths.count))") {
                    if viewModel.completedPaths.isEmpty {
                        Text("No exports yet").foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.completedPaths, id: \.self) { path in
                        Label(path, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }

                Section("Failed (\(viewModel.failureMessages.count))") {
                    ForEach(viewModel.failureMessages, id: \.self) { message in
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("ObjC Bridge Demo")
        }
    }
}
