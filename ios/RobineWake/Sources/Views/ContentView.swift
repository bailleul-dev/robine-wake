import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bluetooth: BluetoothAlarmClient
    @State private var editedAlarm: Alarm?
    @State private var createsAlarm = false
    @State private var wakeChallenge: WakeChallengeRequest?

    var body: some View {
        TabView {
            NavigationStack {
                MorningView(
                    editAlarm: { editedAlarm = $0 },
                    createAlarm: { createsAlarm = true },
                    requestWakeConfirmation: presentWakeChallenge
                )
            }
            .tabItem { Label("Matin", systemImage: "sun.horizon.fill") }

            NavigationStack { EveningView() }
                .tabItem { Label("Soir", systemImage: "moon.stars.fill") }

            NavigationStack {
                AlarmsView(
                    editAlarm: { editedAlarm = $0 },
                    createAlarm: { createsAlarm = true }
                )
            }
            .tabItem { Label("Alarmes", systemImage: "alarm.fill") }

            NavigationStack { SystemView() }
                .tabItem { Label("Réveil", systemImage: "sparkles") }
        }
        .tint(RobineTheme.moon)
        .toolbarBackground(RobineTheme.night900.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .overlay(alignment: .bottom) {
            if let session = bluetooth.activeSession {
                GlobalAlarmControls(session: session) {
                    presentWakeChallenge(session)
                }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 82)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: bluetooth.activeSession?.id)
        .sheet(item: $editedAlarm) { alarm in
            AlarmEditor(draft: AlarmDraft(alarm: alarm, sounds: bluetooth.sounds))
        }
        .sheet(isPresented: $createsAlarm) {
            AlarmEditor(draft: AlarmDraft(sounds: bluetooth.sounds))
        }
        .fullScreenCover(item: $wakeChallenge) { request in
            WakeChallengeView(sessionID: request.id) {
                wakeChallenge = nil
                bluetooth.dismissSession()
            }
        }
        .onChange(of: bluetooth.activeSession?.id) { _, sessionID in
            if sessionID == nil { wakeChallenge = nil }
        }
        .alert("Connexion au réveil", isPresented: errorPresented) {
            Button("Réessayer") {
                bluetooth.lastError = nil
                bluetooth.reconnect()
            }
            Button("Fermer", role: .cancel) { bluetooth.lastError = nil }
        } message: {
            Text(bluetooth.lastError ?? "Une erreur inconnue est survenue.")
        }
        .preferredColorScheme(.dark)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { bluetooth.lastError != nil },
            set: { if !$0 { bluetooth.lastError = nil } }
        )
    }

    private func presentWakeChallenge(_ session: WakeSession) {
        wakeChallenge = WakeChallengeRequest(id: session.id)
    }
}

private struct WakeChallengeRequest: Identifiable {
    let id: String
}

private struct GlobalAlarmControls: View {
    @EnvironmentObject private var bluetooth: BluetoothAlarmClient
    let session: WakeSession
    let requestWakeConfirmation: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative)
                .font(.title3.weight(.semibold))
                .foregroundStyle(RobineTheme.rose)
                .frame(width: 42, height: 42)
                .background(RobineTheme.rose.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Alarme en cours")
                    .font(.subheadline.weight(.bold))
                Text(session.audioPhase == "strong" ? "Son de renfort" : "Réveil progressif")
                    .font(.caption)
                    .foregroundStyle(RobineTheme.muted)
            }

            Spacer(minLength: 4)

            if session.smartphoneDismissAllowed != false {
                Button {
                    requestWakeConfirmation()
                } label: {
                    Label("Je suis levé", systemImage: "sun.max.fill")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .foregroundStyle(RobineTheme.night950)
                        .background(RobineTheme.moon, in: Capsule())
                }
                .disabled(bluetooth.isBusy)
            } else {
                Label("Arrêt sur le réveil", systemImage: "iphone.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RobineTheme.muted)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(RobineTheme.rose.opacity(0.35))
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }
}

private struct MorningView: View {
    @EnvironmentObject private var bluetooth: BluetoothAlarmClient
    let editAlarm: (Alarm) -> Void
    let createAlarm: () -> Void
    let requestWakeConfirmation: (WakeSession) -> Void

    private var nextAlarm: Alarm? {
        bluetooth.alarms.filter(\.enabled).min { lhs, rhs in
            (lhs.nextOccurrences?.first ?? lhs.localTime) < (rhs.nextOccurrences?.first ?? rhs.localTime)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                brandHeader
                clockHero

                if let session = bluetooth.activeSession {
                    ActiveSessionCard(session: session) {
                        requestWakeConfirmation(session)
                    }
                }

                if bluetooth.device?.clockTrusted == false {
                    ClockWarningCard()
                }

                nextWakeCard
                alarmOverview
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .refreshable { bluetooth.refresh() }
        .toolbar(.hidden, for: .navigationBar)
        .robineScreen()
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            CrescentMark(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("ROBINE WAKE")
                    .font(.caption.weight(.bold))
                    .tracking(1.8)
                Text("Un réveil qui commence doucement")
                    .font(.caption)
                    .foregroundStyle(RobineTheme.muted)
            }
            Spacer()
            StatusPill(
                title: bluetooth.connectionLabel,
                connected: bluetooth.canSendCommands,
                busy: bluetooth.isBusy
            )
        }
    }

    private var clockHero: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 8) {
                CrescentMark(size: 48)
                    .padding(.bottom, 5)
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 68, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(RobineTheme.text)
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(RobineTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var nextWakeCard: some View {
        if let alarm = nextAlarm {
            Button { editAlarm(alarm) } label: {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        SectionEyebrow(text: "Prochain réveil", color: RobineTheme.moon)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(RobineTheme.muted)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(alarm.localTime.prefix(5)))
                            .font(.system(size: 46, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Spacer()
                        Text(alarm.label)
                            .font(.headline)
                            .foregroundStyle(RobineTheme.moonSoft)
                    }
                    HStack(spacing: 16) {
                        Label(alarm.scheduleLabel, systemImage: "calendar")
                        Label("\((alarm.prewakeSeconds ?? alarm.volumeProfile.rampSeconds) / 60) min avant", systemImage: "waveform.path")
                    }
                    .font(.caption)
                    .foregroundStyle(RobineTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .robineCard(highlighted: true)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: createAlarm) {
                VStack(spacing: 14) {
                    Image(systemName: "alarm.waves.left.and.right")
                        .font(.system(size: 30))
                        .foregroundStyle(RobineTheme.moon)
                    Text("Préparer votre premier matin")
                        .font(.headline)
                    Text("Choisissez l’heure, le voyage sonore et la montée progressive.")
                        .font(.subheadline)
                        .foregroundStyle(RobineTheme.muted)
                        .multilineTextAlignment(.center)
                    Text("Créer une alarme")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(RobineTheme.moon, in: Capsule())
                        .foregroundStyle(RobineTheme.night950)
                }
                .frame(maxWidth: .infinity)
                .robineCard(highlighted: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var alarmOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionEyebrow(text: "Vos alarmes")
                Spacer()
                Button(action: createAlarm) { Image(systemName: "plus") }
                    .accessibilityLabel("Ajouter une alarme")
            }

            ForEach(bluetooth.alarms.prefix(3)) { alarm in
                Button { editAlarm(alarm) } label: {
                    CompactAlarmRow(alarm: alarm)
                }
                .buttonStyle(.plain)

                if alarm.id != bluetooth.alarms.prefix(3).last?.id {
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }

            if bluetooth.alarms.isEmpty {
                Text("Aucune alarme enregistrée.")
                    .font(.subheadline)
                    .foregroundStyle(RobineTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .robineCard()
    }
}

private struct ActiveSessionCard: View {
    @EnvironmentObject private var bluetooth: BluetoothAlarmClient
    let session: WakeSession
    let requestWakeConfirmation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                SectionEyebrow(text: "Réveil en cours", color: RobineTheme.rose)
                Spacer()
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative)
                    .foregroundStyle(RobineTheme.rose)
            }
            Text(session.audioPhase == "strong" ? "Le son de renfort joue" : "La lumière sonore monte doucement")
                .font(.title3.weight(.semibold))
            HStack(spacing: 12) {
                Button("Répéter") { bluetooth.snooze() }
                    .buttonStyle(RobineSecondaryButtonStyle())
                if session.smartphoneDismissAllowed != false {
                    Button("Je suis levé", action: requestWakeConfirmation)
                        .buttonStyle(RobinePrimaryButtonStyle())
                } else {
                    Label("Arrêt depuis le smartphone désactivé", systemImage: "iphone.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RobineTheme.muted)
                }
            }
        }
        .robineCard(highlighted: true)
    }
}

private struct ClockWarningCard: View {
    @EnvironmentObject private var bluetooth: BluetoothAlarmClient

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .font(.title2)
                .foregroundStyle(RobineTheme.moon)
            VStack(alignment: .leading, spacing: 3) {
                Text("Heure à confirmer")
                    .font(.headline)
                Text("Vérifiez l’heure avant d’activer un réveil.")
                    .font(.caption)
                    .foregroundStyle(RobineTheme.muted)
            }
            Spacer()
            Button("Confirmer") { bluetooth.confirmClock() }
                .font(.caption.weight(.bold))
        }
        .robineCard()
    }
}

private struct AlarmsView: View {
    @EnvironmentObject private var bluetooth: BluetoothAlarmClient
    let editAlarm: (Alarm) -> Void
    let createAlarm: () -> Void
    @State private var alarmToTest: Alarm?
    @State private var strongAlarmToTest: Alarm?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if bluetooth.alarms.isEmpty {
                    VStack(spacing: 16) {
                        CrescentMark(size: 50)
                        Text("Vos matins commencent ici")
                            .font(.title2.weight(.semibold))
                        Text("Créez un réveil à deux étapes, doux puis plus présent si nécessaire.")
                            .foregroundStyle(RobineTheme.muted)
                            .multilineTextAlignment(.center)
                        Button("Créer une alarme", action: createAlarm)
                            .buttonStyle(RobinePrimaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .robineCard(highlighted: true)
                }

                ForEach(bluetooth.alarms) { alarm in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Button { editAlarm(alarm) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(String(alarm.localTime.prefix(5)))
                                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                    Text(alarm.label)
                                        .font(.headline)
                                    Text(alarm.scheduleLabel)
                                        .font(.subheadline)
                                        .foregroundStyle(RobineTheme.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Toggle("", isOn: Binding(
                                get: { alarm.enabled },
                                set: { bluetooth.setEnabled($0, for: alarm) }
                            ))
                            .labelsHidden()
                            .disabled(bluetooth.isBusy)
                        }

                        Divider().overlay(Color.white.opacity(0.08))

                        HStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Label("Doux", systemImage: "speaker.wave.1.fill")
                                Image(systemName: "arrow.right")
                                Label("Renfort", systemImage: "speaker.wave.3.fill")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(RobineTheme.lavender)

                            Spacer()

                            Button {
                                alarmToTest = alarm
                            } label: {
                                Label("Réveil complet", systemImage: "play.fill")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(RobineTheme.night950)
                                    .background(RobineTheme.moon, in: Capsule())
                            }
                            .disabled(!bluetooth.canSendCommands || bluetooth.isBusy)

                            Button {
                                strongAlarmToTest = alarm
                            } label: {
                                Label("Fort", systemImage: "bolt.fill")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(Color.white)
                                    .background(RobineTheme.rose.opacity(0.72), in: Capsule())
                            }
                            .disabled(!bluetooth.canSendCommands || bluetooth.isBusy)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(alarm.enabled ? 1 : 0.55)
                    .robineCard()
                    .contextMenu {
                        Button { alarmToTest = alarm } label: {
                            Label("Lancer le réveil complet", systemImage: "play.fill")
                        }
                        Button { strongAlarmToTest = alarm } label: {
                            Label("Tester la phase forte", systemImage: "bolt.fill")
                        }
                        Button(role: .destructive) { bluetooth.delete(alarm) } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .refreshable { bluetooth.refresh() }
        .navigationTitle("Alarmes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: createAlarm) { Image(systemName: "plus") }
                    .disabled(!bluetooth.canSendCommands || bluetooth.isBusy)
            }
        }
        .confirmationDialog(
            alarmToTest.map { "Lancer « \($0.label) » comme demain matin ?" } ?? "Lancer ce réveil ?",
            isPresented: Binding(
                get: { alarmToTest != nil },
                set: { if !$0 { alarmToTest = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let alarm = alarmToTest {
                Button("Lancer le réveil complet") {
                    bluetooth.trigger(alarm)
                    alarmToTest = nil
                }
            }
            Button("Annuler", role: .cancel) { alarmToTest = nil }
        } message: {
            if let alarm = alarmToTest {
                Text("La séquence réelle démarre maintenant : montée pendant \((alarm.prewakeSeconds ?? alarm.volumeProfile.rampSeconds) / 60) minutes, plafond pendant 5 minutes, puis son de renfort.")
            }
        }
        .confirmationDialog(
            strongAlarmToTest.map { "Tester directement la phase forte de « \($0.label) » ?" } ?? "Tester la phase forte ?",
            isPresented: Binding(
                get: { strongAlarmToTest != nil },
                set: { if !$0 { strongAlarmToTest = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let alarm = strongAlarmToTest {
                Button("Lancer la phase forte") {
                    bluetooth.testStrongAlarm(id: alarm.id)
                    strongAlarmToTest = nil
                }
            }
            Button("Annuler", role: .cancel) { strongAlarmToTest = nil }
        } message: {
            Text("Le son de renfort démarrera au volume maximal configuré et les couleurs alterneront toutes les 3 secondes.")
        }
        .robineScreen()
    }
}

private struct EveningView: View {
    @EnvironmentObject private var bluetooth: BluetoothAlarmClient
    @State private var breathingTargetID = ""
    @State private var breathingDurationMinutes = 10
    @AppStorage("eveningVolumePercent.v4") private var eveningVolumePercent = 60

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                VStack(spacing: 14) {
                    CrescentMark(size: 44)
                    SectionEyebrow(text: "Rituel du soir", color: RobineTheme.twilightRose)
                    Text("Ralentir avant la nuit")
                        .font(.title2.weight(.semibold))
                    Text("Une respiration guidée par la lumière, douce et autonome, pour laisser la journée retomber.")
                        .font(.subheadline)
                        .foregroundStyle(RobineTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .robineCard(highlighted: true)

                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        SectionEyebrow(text: "Respiration 4 / 6", color: RobineTheme.twilightRose)
                        Spacer()
                        Image(systemName: "lightbulb.led.fill")
                            .foregroundStyle(RobineTheme.breathingInhaleAmber)
                    }

                    if bluetooth.hue?.breathing?.active == true,
                       let breathing = bluetooth.hue?.breathing {
                        BreathingGuideView(
                            breathing: breathing,
                            synchronizedAt: bluetooth.breathingSynchronizedAt
                        )

                        Label(
                            breathing.audio?.active == true
                                ? "Jardin sonore synchronisé avec la lumière"
                                : "La lumière continue sans ambiance sonore",
                            systemImage: breathing.audio?.active == true
                                ? "speaker.wave.2.fill"
                                : "speaker.slash.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            breathing.audio?.active == true ? RobineTheme.mint : RobineTheme.rose
                        )

                        volumeControl(isActive: true)

                        Button {
                            bluetooth.stopBreathing()
                        } label: {
                            Label("Terminer et restaurer la lumière", systemImage: "stop.fill")
                        }
                        .buttonStyle(RobinePrimaryButtonStyle())
                        .disabled(bluetooth.isBusy)
                    } else {
                        Text("L’orage reste naturel et constant. La lumière glisse directement de l’ambre doré au rose crépusculaire, sans passer par le blanc ; seule son intensité évolue lentement.")
                            .font(.subheadline)
                            .foregroundStyle(RobineTheme.muted)

                        HStack(spacing: 14) {
                            phaseLegend(color: RobineTheme.breathingInhaleAmber, title: "Inspiration", detail: "4 s · ambre doré · 2 → 30 %")
                            phaseLegend(color: RobineTheme.breathingExhaleRose, title: "Expiration", detail: "6 s · rose crépusculaire · 30 → 2 %")
                        }

                        Picker("Pièce ou zone", selection: $breathingTargetID) {
                            ForEach(bluetooth.hueTargets) { target in
                                Text(target.name).tag(target.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(RobineTheme.moon)

                        Picker("Durée", selection: $breathingDurationMinutes) {
                            ForEach([3, 5, 10, 15, 20, 30], id: \.self) { minutes in
                                Text("\(minutes) minutes").tag(minutes)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(RobineTheme.moon)

                        volumeControl(isActive: false)

                        Button {
                            bluetooth.startBreathing(
                                targetID: breathingTargetID,
                                durationMinutes: breathingDurationMinutes,
                                volumePercent: eveningVolumePercent
                            )
                        } label: {
                            Label("Commencer la séance", systemImage: "play.fill")
                        }
                        .buttonStyle(RobinePrimaryButtonStyle())
                        .disabled(
                            bluetooth.isBusy ||
                            !bluetooth.canSendCommands ||
                            bluetooth.hue?.configured != true ||
                            breathingTargetID.isEmpty
                        )

                        if bluetooth.hue?.configured != true {
                            Label("Configurez d’abord Philips Hue dans l’onglet Réveil.", systemImage: "lightbulb.slash")
                                .font(.caption)
                                .foregroundStyle(RobineTheme.rose)
                        } else if bluetooth.hue?.state != "available" {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Le dernier échange Hue a échoué.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(RobineTheme.rose)
                                Button("Réessayer la connexion Hue") {
                                    bluetooth.refreshHue()
                                }
                                .font(.caption.weight(.semibold))
                                .disabled(!bluetooth.canSendCommands || bluetooth.isBusy)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .robineCard(highlighted: bluetooth.hue?.breathing?.active == true)
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .navigationTitle("Le soir")
        .onAppear {
            selectDefaultBreathingTarget()
            guard bluetooth.canSendCommands else { return }
            if bluetooth.hue?.configured == true {
                bluetooth.refreshHue()
            } else {
                bluetooth.refresh()
            }
        }
        .onChange(of: bluetooth.hueTargets) { _, _ in selectDefaultBreathingTarget() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if bluetooth.hue?.configured == true {
                        bluetooth.refreshHue()
                    } else {
                        bluetooth.refresh()
                    }
                } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(!bluetooth.canSendCommands || bluetooth.isBusy)
            }
        }
        .robineScreen()
    }

    private func phaseLegend(color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(RobineTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
    }

    private func volumeControl(isActive: Bool) -> some View {
        VStack(spacing: 8) {
            HStack {
                Label("Volume", systemImage: eveningVolumePercent == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(eveningVolumePercent) %")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(RobineTheme.moon)
            }

            Slider(
                value: Binding(
                    get: { Double(eveningVolumePercent) },
                    set: { eveningVolumePercent = Int($0.rounded()) }
                ),
                in: 0...100,
                step: 5,
                onEditingChanged: { editing in
                    if !editing && isActive {
                        bluetooth.setBreathingVolume(eveningVolumePercent)
                    }
                }
            )
            .tint(RobineTheme.moon)
            .disabled(bluetooth.isBusy)
            .accessibilityValue("\(eveningVolumePercent) pour cent")
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
    }

    private func selectDefaultBreathingTarget() {
        if let activeVolume = bluetooth.hue?.breathing?.audio?.volumePercent {
            eveningVolumePercent = activeVolume
        }
        if let activeTarget = bluetooth.hue?.breathing?.targetID {
            breathingTargetID = activeTarget
        } else if !bluetooth.hueTargets.contains(where: { $0.id == breathingTargetID }) {
            breathingTargetID = bluetooth.hueTargets.first?.id ?? ""
        }
    }
}

private struct SystemView: View {
    @EnvironmentObject private var bluetooth: BluetoothAlarmClient
    @StateObject private var hueDiscovery = HueBridgeDiscovery()
    @State private var confirmsHistoryErase = false
    @State private var bridgeHost = ""
    @State private var showsManualHueAddress = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionEyebrow(text: "État du réveil", color: RobineTheme.mint)
                    MetricRow(icon: "antenna.radiowaves.left.and.right", title: "Canal actif", detail: bluetooth.connectionLabel, color: RobineTheme.mint)
                    MetricRow(icon: "network", title: "API locale", detail: bluetooth.httpEndpoint?.host ?? "À découvrir", color: RobineTheme.lavender)
                    MetricRow(icon: "wifi", title: "Réseau", detail: label(bluetooth.device?.network.state), color: RobineTheme.lavender)
                    MetricRow(icon: "speaker.wave.2.fill", title: "Audio", detail: label(bluetooth.device?.audio.state), color: RobineTheme.moon)
                    MetricRow(icon: "shippingbox.fill", title: "Logiciel", detail: bluetooth.device?.firmware.version ?? "—", color: RobineTheme.lavender)
                }
                .robineCard()

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        SectionEyebrow(text: "Arrêt de l’alarme", color: RobineTheme.rose)
                        Spacer()
                        Toggle(
                            "Autoriser le smartphone",
                            isOn: Binding(
                                get: { bluetooth.smartphoneDismiss.enabled },
                                set: { bluetooth.setSmartphoneDismissEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .tint(RobineTheme.mint)
                        .disabled(
                            bluetooth.smartphoneDismiss.locked ||
                            bluetooth.activeSession != nil ||
                            bluetooth.isBusy
                        )
                    }

                    Text(
                        bluetooth.smartphoneDismiss.enabled
                            ? "Le smartphone peut arrêter une alarme après le défi de réveil."
                            : "L’alarme doit être arrêtée depuis le réveil ou le bouton déporté."
                    )
                    .font(.subheadline)
                    .foregroundStyle(RobineTheme.muted)

                    if bluetooth.smartphoneDismiss.locked || bluetooth.activeSession != nil {
                        Label(
                            "Réglage verrouillé jusqu’à la fin de l’alarme en cours.",
                            systemImage: "lock.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RobineTheme.moon)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .robineCard(highlighted: !bluetooth.smartphoneDismiss.enabled)

                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        SectionEyebrow(text: "Philips Hue", color: RobineTheme.moon)
                        Spacer()
                        Image(systemName: "lightbulb.2.fill")
                            .foregroundStyle(RobineTheme.moon)
                    }

                    if bluetooth.hue?.configured == true {
                        MetricRow(
                            icon: "point.3.connected.trianglepath.dotted",
                            title: "Pont local",
                            detail: bluetooth.hue?.bridgeHost ?? "Connecté",
                            color: bluetooth.hue?.state == "available" ? RobineTheme.mint : RobineTheme.rose
                        )
                        MetricRow(
                            icon: "rectangle.3.group.fill",
                            title: "Pièces et zones",
                            detail: "\(bluetooth.hue?.targetCount ?? 0) disponibles",
                            color: RobineTheme.lavender
                        )

                        HStack(spacing: 10) {
                            Button("Actualiser") { bluetooth.refreshHue() }
                                .buttonStyle(RobineSecondaryButtonStyle())
                            Button("Déconnecter", role: .destructive) { bluetooth.disconnectHue() }
                                .buttonStyle(RobineSecondaryButtonStyle())
                        }
                    } else {
                        Text("Les ponts Hue présents sur le même réseau sont découverts automatiquement. Appuyez sur le bouton rond du pont juste avant de le connecter.")
                            .font(.subheadline)
                            .foregroundStyle(RobineTheme.muted)

                        switch hueDiscovery.state {
                        case .searching:
                            HStack(spacing: 10) {
                                ProgressView().tint(RobineTheme.moon)
                                Text("Recherche des ponts Hue…")
                                    .font(.subheadline)
                                    .foregroundStyle(RobineTheme.muted)
                            }

                        case .found:
                            ForEach(hueDiscovery.bridges) { bridge in
                                Button {
                                    bridgeHost = bridge.host
                                    bluetooth.pairHue(bridgeHost: bridge.host)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "network.badge.shield.half.filled")
                                            .foregroundStyle(RobineTheme.moon)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(bridge.name).font(.subheadline.weight(.semibold))
                                            Text(bridge.host).font(.caption).foregroundStyle(RobineTheme.muted)
                                        }
                                        Spacer()
                                        if bluetooth.isPairingHue {
                                            ProgressView().tint(RobineTheme.moon)
                                            Text("Association…").font(.caption.weight(.bold))
                                        } else {
                                            Text("Connecter").font(.caption.weight(.bold))
                                            Image(systemName: "chevron.right").font(.caption)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
                                }
                                .buttonStyle(.plain)
                                .disabled(!bluetooth.canSendCommands || bluetooth.isBusy)
                            }

                            if !bluetooth.canSendCommands {
                                Label("Le réveil Raspberry n’est pas connecté. Rétablissez sa connexion avant d’associer le pont.", systemImage: "antenna.radiowaves.left.and.right.slash")
                                    .font(.caption)
                                    .foregroundStyle(RobineTheme.rose)
                            }

                        case .unavailable:
                            Label("Aucun pont résolu. Vérifiez l’accès au réseau local ou utilisez l’adresse manuelle.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(RobineTheme.rose)

                        case .idle:
                            EmptyView()
                        }

                        Button("Rechercher à nouveau") { hueDiscovery.start() }
                            .font(.caption.weight(.semibold))
                            .disabled(hueDiscovery.state == .searching)

                        DisclosureGroup("Adresse manuelle", isExpanded: $showsManualHueAddress) {
                            VStack(spacing: 10) {
                                TextField("Ex. 192.168.1.42", text: $bridgeHost)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                    .padding(12)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))

                                Button("Connecter cette adresse") { bluetooth.pairHue(bridgeHost: bridgeHost) }
                                    .buttonStyle(RobinePrimaryButtonStyle())
                                    .disabled(bridgeHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !bluetooth.canSendCommands || bluetooth.isBusy)
                            }
                            .padding(.top, 10)
                        }
                        .font(.subheadline)
                    }

                    if bluetooth.hue?.state == "unavailable" {
                        Label("Le pont est enregistré mais momentanément inaccessible.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(RobineTheme.rose)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .robineCard(highlighted: bluetooth.hue?.state == "available")

                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        SectionEyebrow(text: "Bouton déporté", color: RobineTheme.mint)
                        Spacer()
                        Image(systemName: "button.programmable")
                            .foregroundStyle(RobineTheme.mint)
                    }

                    Text("Arrêt sécurisé en LoRa 868 MHz. Le Raspberry écoute directement le bouton, sans Internet ni routeur. Chaque appui est signé et protégé contre le rejeu.")
                        .font(.subheadline)
                        .foregroundStyle(RobineTheme.muted)

                    ForEach(bluetooth.remoteButton?.buttons ?? []) { button in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(RobineTheme.mint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(button.name).font(.subheadline.weight(.semibold))
                                Text(button.lastSeenAt?.shortDateTime ?? "Jamais utilisé")
                                    .font(.caption)
                                    .foregroundStyle(RobineTheme.muted)
                            }
                            Spacer()
                            Button("Oublier", role: .destructive) {
                                bluetooth.removeRemoteButton(id: button.id)
                            }
                            .font(.caption.weight(.semibold))
                            .disabled(bluetooth.isBusy)
                        }
                    }

                    if bluetooth.remoteButton?.pairing.active == true {
                        Label("Association ouverte pendant 2 minutes. Maintenez maintenant le bouton physique enfoncé.", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(RobineTheme.moon)
                    } else {
                        Button("Associer un bouton") { bluetooth.beginRemoteButtonPairing() }
                            .buttonStyle(RobinePrimaryButtonStyle())
                            .disabled(!bluetooth.canSendCommands || bluetooth.isBusy)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .robineCard(highlighted: bluetooth.remoteButton?.pairing.active == true)

                VStack(alignment: .leading, spacing: 15) {
                    SectionEyebrow(text: "Bibliothèque sonore", color: RobineTheme.moon)
                    ForEach(bluetooth.sounds.prefix(8)) { sound in
                        HStack(spacing: 12) {
                            Image(systemName: sound.intensity == "strong" ? "waveform.badge.plus" : "waveform")
                                .foregroundStyle(sound.intensity == "strong" ? RobineTheme.rose : RobineTheme.moon)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sound.title).font(.subheadline.weight(.medium))
                                if let artist = sound.artist {
                                    Text(artist).font(.caption).foregroundStyle(RobineTheme.muted)
                                }
                            }
                            Spacer()
                            Text(sound.intensity?.capitalized ?? "")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(RobineTheme.muted)
                        }
                    }
                }
                .robineCard()

                if !bluetooth.recentSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionEyebrow(text: "Matins récents")
                            Spacer()
                            Button("Effacer", role: .destructive) { confirmsHistoryErase = true }
                                .font(.caption)
                        }
                        ForEach(bluetooth.recentSessions.prefix(5)) { session in
                            MetricRow(
                                icon: session.state == "dismissed" ? "checkmark.circle.fill" : "clock.fill",
                                title: session.state?.capitalized ?? "Session",
                                detail: session.endedAt?.shortDateTime ?? "—",
                                color: session.state == "dismissed" ? RobineTheme.mint : RobineTheme.lavender
                            )
                        }
                    }
                    .robineCard()
                }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .navigationTitle("Le réveil")
        .onAppear {
            if bluetooth.hue?.configured != true { hueDiscovery.start() }
        }
        .onDisappear { hueDiscovery.stop() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { bluetooth.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(!bluetooth.canSendCommands || bluetooth.isBusy)
            }
        }
        .confirmationDialog("Effacer tout l’historique ?", isPresented: $confirmsHistoryErase, titleVisibility: .visible) {
            Button("Effacer l’historique", role: .destructive) { bluetooth.eraseHistory() }
        }
        .robineScreen()
    }

    private func label(_ state: String?) -> String {
        switch state {
        case "available": return "Disponible"
        case "unavailable": return "Indisponible"
        default: return state?.capitalized ?? "—"
        }
    }

}

private struct BreathingGuideView: View {
    let breathing: HueStatus.Breathing
    let synchronizedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let progress = phaseProgress(at: context.date)
            let inhales = breathing.phase == "inhale"
            let scale = inhales ? 0.68 + 0.32 * progress : 1.0 - 0.32 * progress
            let phaseColor = inhales ? RobineTheme.breathingInhaleAmber : RobineTheme.breathingExhaleRose

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(phaseColor.opacity(0.12))
                        .frame(width: 150, height: 150)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [phaseColor, phaseColor.opacity(0.38)],
                                center: .center,
                                startRadius: 4,
                                endRadius: 74
                            )
                        )
                        .frame(width: 132, height: 132)
                        .scaleEffect(scale)
                        .shadow(color: phaseColor.opacity(0.32), radius: 18)
                    Text(inhales ? "Inspirez" : "Expirez")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(RobineTheme.night950)
                }

                VStack(spacing: 3) {
                    Text("Cycle \((breathing.cycleCount ?? 0) + 1)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(RobineTheme.moon)
                        .monospacedDigit()
                    Text("\(breathing.cycleCount ?? 0) cycles terminés · \(breathing.targetName ?? "Lumière Hue")")
                        .font(.caption)
                        .foregroundStyle(RobineTheme.muted)
                }

                if let remaining = remainingTime(at: context.date) {
                    Text("Encore \(remaining)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RobineTheme.moon)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(inhales ? "Inspirez pendant 4 secondes" : "Expirez pendant 6 secondes")
        }
    }

    private func phaseProgress(at date: Date) -> Double {
        if let duration = breathing.phaseDurationMilliseconds,
           let elapsed = breathing.phaseElapsedMilliseconds,
           let synchronizedAt,
           duration > 0 {
            let sinceSynchronization = max(date.timeIntervalSince(synchronizedAt) * 1_000, 0)
            return min(max((Double(elapsed) + sinceSynchronization) / Double(duration), 0), 1)
        }

        guard let rawDate = breathing.phaseStartedAt,
              let startedAt = parseISO8601(rawDate) else { return 0 }

        let duration = Double(breathing.phase == "inhale" ? 4 : 6)
        return min(max(date.timeIntervalSince(startedAt) / duration, 0), 1)
    }

    private func remainingTime(at date: Date) -> String? {
        if let remaining = breathing.remainingSeconds, let synchronizedAt {
            let elapsed = max(Int(date.timeIntervalSince(synchronizedAt)), 0)
            let seconds = max(remaining - elapsed, 0)
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }

        guard let rawDate = breathing.endsAt,
              let endsAt = parseISO8601(rawDate) else { return nil }

        let seconds = max(Int(endsAt.timeIntervalSince(date).rounded(.up)), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct CompactAlarmRow: View {
    let alarm: Alarm

    var body: some View {
        HStack(spacing: 13) {
            Text(String(alarm.localTime.prefix(5)))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text(alarm.label).font(.subheadline.weight(.medium))
                Text(alarm.scheduleLabel).font(.caption).foregroundStyle(RobineTheme.muted)
            }
            Spacer()
            Circle()
                .fill(alarm.enabled ? RobineTheme.mint : RobineTheme.muted)
                .frame(width: 7, height: 7)
        }
        .opacity(alarm.enabled ? 1 : 0.55)
    }
}

struct RobinePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(RobineTheme.night950)
            .background(RobineTheme.moon.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct RobineSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(RobineTheme.text)
            .background(Color.white.opacity(configuration.isPressed ? 0.06 : 0.1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1)))
    }
}

private extension Alarm {
    var scheduleLabel: String {
        let weekdays = [1: "lun", 2: "mar", 3: "mer", 4: "jeu", 5: "ven", 6: "sam", 7: "dim"]
        if daysOfWeek == Array(1...7) { return "Tous les jours" }
        if daysOfWeek == Array(1...5) { return "En semaine" }
        return daysOfWeek.compactMap { weekdays[$0] }.joined(separator: " · ")
    }
}

private extension String {
    var shortDateTime: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: self) else { return self }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
