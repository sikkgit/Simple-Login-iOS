//
//  AliasesView.swift
//  SimpleLogin
//
//  Created by Thanh-Nhon Nguyen on 02/09/2021.
//

import AlertToast
import Combine
import Introspect
import SimpleLoginPackage
import SwiftUI

struct AliasesView: View {
    @EnvironmentObject private var session: Session
    @AppStorage(kHapticFeedbackEnabled) private var hapticFeedbackEnabled = true
    @StateObject private var viewModel = AliasesViewModel()
    @State private var showingRandomAliasActionSheet = false
    @State private var showingUpdatingAlert = false
    @State private var showingSearchView = false
    @State private var showingCreateView = false
    @State private var copiedEmail: String?
    @State private var createdAlias: Alias?
    @State private var showingAliasDetail = false
    @State private var showingAliasContacts = false
    @State private var selectedAlias: Alias = .ccohen
    private let refreshControl = UIRefreshControl()

    enum Modal {
        case search, create
    }

    var body: some View {
        let showingCopiedEmailAlert = Binding<Bool>(get: {
            copiedEmail != nil
        }, set: { isShowing in
            if !isShowing {
                copiedEmail = nil
            }
        })

        let showingErrorAlert = Binding<Bool>(get: {
            viewModel.error != nil
        }, set: { isShowing in
            if !isShowing {
                viewModel.handledError()
            }
        })

        let showingCreatedAliasAlert = Binding<Bool>(get: {
            createdAlias != nil
        }, set: { isShowing in
            if !isShowing {
                createdAlias = nil
            }
        })

        NavigationView {
            ScrollView {
                NavigationLink(
                    isActive: $showingAliasDetail,
                    destination: {
                        AliasDetailView(
                            alias: selectedAlias,
                            onUpdateAlias: { updatedAlias in
                                viewModel.update(alias: updatedAlias)
                            },
                            onDeleteAlias: {
                                viewModel.delete(alias: selectedAlias)
                            })
                    },
                    label: { EmptyView() })

                NavigationLink(
                    isActive: $showingAliasContacts,
                    destination: {
                        AliasContactsView(alias: selectedAlias)
                    },
                    label: { EmptyView() })
                LazyVStack {
                    ForEach(viewModel.filteredAliases, id: \.id) { alias in
                        AliasCompactView(
                            alias: alias,
                            onCopy: {
                                if hapticFeedbackEnabled {
                                    Vibration.soft.vibrate()
                                }
                                copiedEmail = alias.email
                                UIPasteboard.general.string = alias.email
                            },
                            onSendMail: {
                                selectedAlias = alias
                                showingAliasContacts = true
                            },
                            onToggle: {
                                viewModel.toggle(alias: alias, session: session)
                            })
                            .padding(.horizontal, 4)
                            .onAppear {
                                viewModel.getMoreAliasesIfNeed(session: session, currentAlias: alias)
                            }
                            .onTapGesture {
                                selectedAlias = alias
                                showingAliasDetail = true
                            }
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .padding()
                    }
                }
                .padding(.vertical, 8)
                .animation(.default)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem {
                    AliasesViewToolbar(selectedStatus: $viewModel.selectedStatus,
                                       onSearch: { showingSearchView = true },
                                       onRandomAlias: { showingRandomAliasActionSheet.toggle() },
                                       onCreateAlias: { showingCreateView = true })
                }
            }
            .introspectScrollView { scrollView in
                refreshControl.addAction(UIAction { _ in
                    viewModel.refresh(session: session)
                }, for: .valueChanged)
                scrollView.refreshControl = refreshControl
            }
            .actionSheet(isPresented: $showingRandomAliasActionSheet) {
                randomAliasActionSheet
            }
            .fullScreenCover(isPresented: $showingSearchView) {
                SearchAliasesView()
                    .forceDarkModeIfApplicable()
            }
        }
        .onAppear {
            viewModel.getMoreAliasesIfNeed(session: session, currentAlias: nil)
        }
        .onReceive(Just(viewModel.isRefreshing)) { isRefreshing in
            if !isRefreshing {
                refreshControl.endRefreshing()
            }
        }
        .onReceive(Just(viewModel.isUpdating)) { isUpdating in
            showingUpdatingAlert = isUpdating
        }
        .sheet(isPresented: $showingCreateView) {
            CreateAliasView { createdAlias in
                self.createdAlias = createdAlias
                viewModel.refresh(session: session)
            }
            .forceDarkModeIfApplicable()
        }
        .toast(isPresenting: showingCopiedEmailAlert) {
            AlertToast(displayMode: .alert,
                       type: .systemImage("doc.on.doc", .secondary),
                       title: "Copied",
                       subTitle: copiedEmail ?? "")
        }
        .toast(isPresenting: showingErrorAlert) {
            AlertToast.errorAlert(message: viewModel.error?.description)
        }
        .toast(isPresenting: $showingUpdatingAlert) {
            AlertToast(type: .loading)
        }
        .toast(isPresenting: showingCreatedAliasAlert) {
            AlertToast(displayMode: .alert,
                       type: .complete(.green),
                       title: "Created",
                       subTitle: createdAlias?.email ?? "")
        }
    }

    private var randomAliasActionSheet: ActionSheet {
        ActionSheet(title: Text("New alias"),
                    message: Text("Randomly create an alias"),
                    buttons: [
                        .default(Text("By random words")) {
                            viewModel.random(mode: .word, session: session)
                        },
                        .default(Text("By UUID")) {
                            viewModel.random(mode: .uuid, session: session)
                        },
                        .cancel(Text("Cancel"))
                    ])
    }
}

enum AliasStatus: CustomStringConvertible, CaseIterable {
    case all, active, inactive

    var description: String {
        switch self {
        case .all: return "All"
        case .active: return "Active"
        case .inactive: return "Inactive"
        }
    }
}

struct AliasesViewToolbar: View {
    @AppStorage(kHapticFeedbackEnabled) private var hapticEffectEnabled = true
    @Binding var selectedStatus: AliasStatus
    let onSearch: () -> Void
    let onRandomAlias: () -> Void
    let onCreateAlias: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Picker("", selection: $selectedStatus) {
                ForEach(AliasStatus.allCases, id: \.self) { status in
                    Text(status.description)
                        .tag(status)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()

            Divider()
                .fixedSize()
                .padding(.horizontal, 16)

//            Button(action: onSearch) {
//                Image(systemName: "magnifyingglass")
//            }
//
//            Spacer()
//                .frame(width: 24)

            Button(action: onRandomAlias) {
                Image(systemName: "shuffle")
            }

            Spacer()
                .frame(width: 24)

            Button(action: {
                if hapticEffectEnabled {
                    Vibration.light.vibrate()
                }
                onCreateAlias()
            }, label: {
                Image(systemName: "plus")
            })
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
    }
}
