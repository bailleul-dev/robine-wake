import SwiftUI

struct AlarmEditor: View {
    @EnvironmentObject private var bluetooth: BluetoothAlarmClient
    @Environment(\.dismiss) private var dismiss
    @State var draft: AlarmDraft
    @State private var confirmsTest = false
    @State private var confirmsStrongTest = false

    private let weekdays = [
        (1, "L"), (2, "M"), (3, "M"), (4, "J"), (5, "V"), (6, "S"), (7, "D")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    timeHero
                    scheduleCard
                    soundJourneyCard
                    lightJourneyCard
                    rampCard
                    snoozeCard

                    if draft.id != nil {
                        testCard
                    }

                    Button(draft.id == nil ? "Créer l’alarme" : "Enregistrer les changements") {
                        bluetooth.save(draft)
                        dismiss()
                    }
                    .buttonStyle(RobinePrimaryButtonStyle())
                    .disabled(!isValid || bluetooth.isBusy)
                    .padding(.top, 4)
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .navigationTitle(draft.id == nil ? "Nouvelle alarme" : "Modifier l’alarme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .confirmationDialog(
                "Lancer « \(draft.label) » comme demain matin ?",
                isPresented: $confirmsTest,
                titleVisibility: .visible
            ) {
                if let alarmID = draft.id {
                    Button("Lancer le réveil complet") { bluetooth.launchFullAlarm(id: alarmID) }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("La séquence réelle démarre maintenant : montée pendant \(draft.prewakeMinutes) minutes, plafond pendant 5 minutes, puis son de renfort. Vous pourrez l’arrêter depuis l’écran Matin.")
            }
            .confirmationDialog(
                "Tester directement la phase forte de « \(draft.label) » ?",
                isPresented: $confirmsStrongTest,
                titleVisibility: .visible
            ) {
                if let alarmID = draft.id {
                    Button("Lancer la phase forte") { bluetooth.testStrongAlarm(id: alarmID) }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Le son de renfort jouera au volume maximal configuré et les couleurs alterneront toutes les 3 secondes.")
            }
            .robineScreen()
        }
        .preferredColorScheme(.dark)
        .task { enableHueForNewAlarmIfAvailable() }
        .onChange(of: bluetooth.hueTargets) { _, _ in enableHueForNewAlarmIfAvailable() }
    }

    private var timeHero: some View {
        VStack(spacing: 12) {
            SectionEyebrow(text: "Quand commence le matin ?", color: RobineTheme.moon)
            DatePicker("Heure", selection: timeBinding, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.wheel)
                .frame(height: 126)
                .clipped()
            TextField("Nom du réveil", text: $draft.label)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
            Toggle("Alarme active", isOn: $draft.enabled)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .robineCard(highlighted: true)
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeading(number: "1", title: "Votre rythme", subtitle: "Les jours où cette alarme revient")

            HStack(spacing: 7) {
                ForEach(weekdays, id: \.0) { day, label in
                    Button(label) { toggle(day) }
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .foregroundStyle(draft.daysOfWeek.contains(day) ? RobineTheme.night950 : RobineTheme.muted)
                        .background(
                            draft.daysOfWeek.contains(day) ? RobineTheme.moon : Color.white.opacity(0.06),
                            in: Circle()
                        )
                        .accessibilityLabel(dayName(day))
                        .accessibilityAddTraits(draft.daysOfWeek.contains(day) ? .isSelected : [])
                }
            }

            Label(TimeZone.current.localizedName(for: .standard, locale: .current) ?? draft.timezone, systemImage: "globe.europe.africa.fill")
                .font(.caption)
                .foregroundStyle(RobineTheme.muted)
        }
        .robineCard()
    }

    private var soundJourneyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeading(number: "2", title: "Voyage sonore", subtitle: "Doux d’abord, plus présent ensuite")

            soundPicker(
                label: "Première lumière",
                detail: "Commence en douceur",
                icon: "sunrise.fill",
                color: RobineTheme.moon,
                selection: $draft.soundID
            )

            HStack(spacing: 10) {
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                Image(systemName: "arrow.down").foregroundStyle(RobineTheme.muted)
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            }

            soundPicker(
                label: "Renfort",
                detail: "Prend le relais si nécessaire",
                icon: "waveform.badge.plus",
                color: RobineTheme.rose,
                selection: $draft.strongSoundID
            )

            Label("La sortie locale du réveil reste prioritaire pendant une alarme.", systemImage: "airplayaudio")
                .font(.caption)
                .foregroundStyle(RobineTheme.muted)
        }
        .robineCard()
    }

    private var rampCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeading(number: "4", title: "Montée progressive", subtitle: "Le plafond est atteint à l’heure du réveil")

            valueSlider(
                title: "Départ",
                value: $draft.startVolume,
                range: 0...min(100, draft.ceilingVolume),
                suffix: "%",
                color: RobineTheme.mint
            )
            valueSlider(
                title: "Plafond",
                value: $draft.ceilingVolume,
                range: max(0, draft.startVolume)...100,
                suffix: "%",
                color: RobineTheme.rose
            )
            valueSlider(
                title: "Commencer avant l’heure",
                value: $draft.prewakeMinutes,
                range: 1...60,
                suffix: " min avant",
                color: RobineTheme.lavender
            )

            Text("Le volume reste au plafond pendant 5 minutes à l’heure choisie, puis le son de renfort prend le relais.")
                .font(.caption)
                .foregroundStyle(RobineTheme.muted)

            HStack(spacing: 4) {
                ForEach(0..<12, id: \.self) { index in
                    Capsule()
                        .fill(index < Int(Double(draft.ceilingVolume) / 100 * 12) ? RobineTheme.lavender.opacity(0.35 + Double(index) * 0.045) : Color.white.opacity(0.05))
                        .frame(height: 5 + CGFloat(index) * 1.5)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
        }
        .robineCard()
    }

    private var snoozeCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            cardHeading(number: "5", title: "Répétition", subtitle: "Une pause avant de relancer le réveil")

            Toggle("Autoriser la répétition", isOn: $draft.snoozeEnabled)
                .font(.subheadline.weight(.semibold))

            if draft.snoozeEnabled {
                Stepper("Pause de \(draft.snoozeMinutes) min", value: $draft.snoozeMinutes, in: 1...30)
                Stepper("Maximum \(draft.snoozeMaximum) fois", value: $draft.snoozeMaximum, in: 1...10)
            }
        }
        .robineCard()
    }

    private var lightJourneyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeading(number: "3", title: "Lever de lumière", subtitle: "Une ambiance Philips Hue progressive")

            if bluetooth.hue?.configured == true, !bluetooth.hueTargets.isEmpty {
                Toggle("Allumer progressivement", isOn: lightEnabledBinding)
                    .font(.subheadline.weight(.semibold))

                if draft.lightEnabled {
                    Picker("Pièce ou zone", selection: lightTargetBinding) {
                        ForEach(bluetooth.hueTargets) { target in
                            Text(target.name).tag(target.id)
                        }
                    }

                    valueSlider(
                        title: "Première lueur",
                        value: $draft.lightStartBrightness,
                        range: 1...min(100, draft.lightEndBrightness),
                        suffix: "%",
                        color: RobineTheme.moon
                    )
                    valueSlider(
                        title: "Lumière finale",
                        value: $draft.lightEndBrightness,
                        range: max(1, draft.lightStartBrightness)...100,
                        suffix: "%",
                        color: RobineTheme.mint
                    )
                    valueSlider(
                        title: "Durée lumière",
                        value: $draft.lightRampMinutes,
                        range: 1...60,
                        suffix: " min",
                        color: RobineTheme.lavender
                    )

                    Picker("Après l’arrêt", selection: $draft.lightEndBehavior) {
                        Text("Restaurer").tag("restore")
                        Text("Éteindre").tag("off")
                        Text("Laisser").tag("leave")
                    }
                    .pickerStyle(.segmented)
                }
            } else if draft.lightEnabled {
                Toggle("Allumer progressivement", isOn: $draft.lightEnabled)
                    .font(.subheadline.weight(.semibold))
                Label(
                    "La cible \(draft.lightTargetName ?? "Hue enregistrée") est momentanément indisponible. Désactivez-la ou reconnectez le pont.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(RobineTheme.rose)
            } else {
                Label("Connectez d’abord un pont depuis l’onglet Réveil.", systemImage: "lightbulb.slash")
                    .font(.subheadline)
                    .foregroundStyle(RobineTheme.muted)
            }
        }
        .robineCard()
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundStyle(RobineTheme.moon)
                    .frame(width: 42, height: 42)
                    .background(RobineTheme.moon.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lancer ce réveil")
                        .font(.headline)
                    Text("Reproduit exactement la séquence du matin")
                        .font(.caption)
                        .foregroundStyle(RobineTheme.muted)
                }
            }

            HStack(spacing: 10) {
                Button("Réveil complet") { confirmsTest = true }
                    .buttonStyle(RobineSecondaryButtonStyle())
                Button("Tester fort") { confirmsStrongTest = true }
                    .buttonStyle(RobinePrimaryButtonStyle())
            }
            .disabled(!bluetooth.canSendCommands || bluetooth.isBusy)
        }
        .robineCard()
    }

    private func cardHeading(number: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.caption.weight(.heavy))
                .foregroundStyle(RobineTheme.night950)
                .frame(width: 28, height: 28)
                .background(RobineTheme.moon, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(RobineTheme.muted)
            }
        }
    }

    private func soundPicker(
        label: String,
        detail: String,
        icon: String,
        color: Color,
        selection: Binding<String>
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(RobineTheme.muted)
            }
            Spacer()
            Picker(label, selection: selection) {
                ForEach(bluetooth.sounds) { sound in
                    Text(sound.title).tag(sound.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 145, alignment: .trailing)
        }
    }

    private func valueSlider(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        suffix: String,
        color: Color
    ) -> some View {
        VStack(spacing: 9) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(value.wrappedValue)\(suffix)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(color)
        }
    }

    private var isValid: Bool {
        !draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !draft.daysOfWeek.isEmpty &&
            draft.startVolume <= draft.ceilingVolume &&
            (!draft.lightEnabled || draft.lightTargetID != nil) &&
            !draft.soundID.isEmpty &&
            !draft.strongSoundID.isEmpty
    }

    private var lightEnabledBinding: Binding<Bool> {
        Binding(
            get: { draft.lightEnabled },
            set: { enabled in
                draft.lightEnabled = enabled
                if enabled, draft.lightTargetID == nil, let first = bluetooth.hueTargets.first {
                    draft.lightTargetID = first.id
                    draft.lightTargetName = first.name
                }
            }
        )
    }

    private func enableHueForNewAlarmIfAvailable() {
        guard draft.id == nil, !draft.lightEnabled, let first = bluetooth.hueTargets.first else { return }
        draft.lightEnabled = true
        draft.lightTargetID = first.id
        draft.lightTargetName = first.name
    }

    private var lightTargetBinding: Binding<String> {
        Binding(
            get: { draft.lightTargetID ?? bluetooth.hueTargets.first?.id ?? "" },
            set: { id in
                draft.lightTargetID = id
                draft.lightTargetName = bluetooth.hueTargets.first(where: { $0.id == id })?.name
            }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(get: { draft.time }, set: { draft.time = $0 })
    }

    private func toggle(_ day: Int) {
        if draft.daysOfWeek.contains(day) {
            draft.daysOfWeek.remove(day)
        } else {
            draft.daysOfWeek.insert(day)
        }
    }

    private func dayName(_ day: Int) -> String {
        [1: "Lundi", 2: "Mardi", 3: "Mercredi", 4: "Jeudi", 5: "Vendredi", 6: "Samedi", 7: "Dimanche"][day] ?? "Jour"
    }
}
