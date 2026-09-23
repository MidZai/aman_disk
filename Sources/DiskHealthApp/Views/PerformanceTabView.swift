import SwiftUI
import DiskHealthCore
import BenchmarkCore

struct PerformanceTabView: View {
    let disk: RealDisk
    @StateObject private var vm: PerformanceViewModel
    
    init(disk: RealDisk) {
        self.disk = disk
        _vm = StateObject(wrappedValue: PerformanceViewModel(disk: disk, appManager: AppManager.sharedInstance!))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            settingsBar
            Divider()
            
            if vm.isViewingHistory {
                HStack {
                    if let d = vm.lastResult?.date {
                        Text("Résultat du \(Formatters.date(d))")
                            .font(.headline)
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    Button("Revenir au test actuel") {
                        vm.isViewingHistory = false
                        vm.lastResult = nil 
                    }
                }.padding()
            }
            
            gridAndUnits
            Divider()
            bottomStrip
            Divider()
            historyList
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .sheet(isPresented: $vm.showConfirm) { confirmSheet }
        .onChange(of: vm.selectedSize, perform: { _ in vm.refreshTargets() })
        .background(
            Button("") {
                if let res = vm.lastResult {
                    ExportService.copyBenchmarkSummary(result: res)
                    ToastCenter.shared.show(message: "Résultat copié", systemImage: "doc.on.doc")
                }
            }
            .keyboardShortcut("c", modifiers: .command)
            .opacity(0)
        )
    }
    
    private var settingsBar: some View {
        HStack(spacing: 20) {
            Picker("Volume", selection: $vm.selectedTargetId) {
                ForEach(vm.targets, id: \.id) { t in
                    Text(t.label).tag(t.id)
                }
            }
            .frame(width: 250)
            .help(Strings.benchHelpVolume)
            
            Picker("Profil", selection: $vm.selectedProfile) {
                Text(BenchProfile.quick.label).tag(BenchProfile.quick)
                Text(BenchProfile.standard.label).tag(BenchProfile.standard)
                Text(BenchProfile.readOnly.label).tag(BenchProfile.readOnly)
            }
            .frame(width: 150)
            .help(Strings.benchHelpProfile)
            
            Picker("Taille", selection: $vm.selectedSize) {
                Text("1 Gio").tag(UInt64(1073741824))
                Text("4 Gio").tag(UInt64(4294967296))
                Text("16 Gio").tag(UInt64(17179869184))
            }
            .frame(width: 120)
            .help(Strings.benchHelpSize)
            
            Spacer()
            
            let cantRun = vm.targets.first(where: { $0.id == vm.selectedTargetId })?.rejectionReason != nil
            
            if vm.isRunning {
                Button(action: { vm.stop() }) {
                    Label("Arrêter", systemImage: "stop.fill")
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button(action: {
                    if !cantRun { vm.showConfirm = true }
                }) {
                    Label("Lancer", systemImage: "play.fill")
                }
                .disabled(cantRun)
            }
        }
    }
    
    private var gridAndUnits: some View {
        VStack {
            HStack {
                Spacer()
                Picker("", selection: $vm.selectedUnit) {
                    Text("Mo/s").tag(BenchUnit.mbps)
                    Text("IOPS").tag(BenchUnit.iops)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            .padding(.bottom, 8)
            
            BenchGridView(currentState: vm.currentState, result: vm.lastResult, unit: vm.selectedUnit)
        }
        .padding(.vertical)
    }
    
    private var bottomStrip: some View {
        HStack {
            Text(vm.bottomStripText)
            Spacer()
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding()
    }
    
    private var historyList: some View {
        VStack(alignment: .leading) {
            Text("Historique").font(.headline).padding(.horizontal).padding(.top, 8)
                        List {
                ForEach(Array(vm.history.prefix(5))) { res in
                Button(action: {
                    vm.lastResult = res
                    vm.isViewingHistory = true
                }) {
                    HStack {
                        Text(Formatters.date(res.date))
                        Text(res.profile.label)
                        Spacer()
                        if res.completed {
                            if let seqRead = res.tests.first(where: { $0.spec.id == "SEQ1M_QD8" && $0.direction == .read }), let pass = BenchMath.best(seqRead.passes) {
                                Text("L: \(Formatters.speed(BenchMath.megabytesPerSecond(bytes: pass.bytes, seconds: pass.seconds)))")
                            }
                            if let seqWrite = res.tests.first(where: { $0.spec.id == "SEQ1M_QD8" && $0.direction == .write }), let pass = BenchMath.best(seqWrite.passes) {
                                Text("É: \(Formatters.speed(BenchMath.megabytesPerSecond(bytes: pass.bytes, seconds: pass.seconds)))")
                            }
                        } else {
                            Text("Incomplet").foregroundColor(.red)
                        }
                    }
                }
                .buttonStyle(.plain)
                }
            }
            .listStyle(.inset)
            .frame(height: 150)
        }
    }

    private var confirmSheet: some View {
        let vName = vm.targets.first(where: { $0.id == vm.selectedTargetId })?.volume.name ?? "Inconnu"
        let msg = Strings.benchConfirmMessage(volume: vName, size: Formatters.bytes(vm.selectedSize), duration: "environ \(vm.estTimeMin) min", maxWritten: String(format: "%.1f Gio", vm.maxWrittenGB))
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Lancer le test de performances ?").font(.headline)
            Text(msg).fixedSize(horizontal: false, vertical: true)
            if disk.physical.isInternal {
                Text(Strings.benchConfirmInternal).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { vm.showConfirm = false }.keyboardShortcut(.cancelAction)
                Button("Lancer le test") { vm.showConfirm = false; vm.start() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 450)
    }
}
