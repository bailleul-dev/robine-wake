# 00-002 — Gentle Awakening Mechanisms

## Status and scope

Status: research baseline and product design input, not a medical claim.

Last literature search: 2026-08-20. Product scope revised: 2026-09-06.
Camera, bed-presence feedback and automatic bed-exit dismissal are removed.
The calibrated envelope below remains a design target, not a claim of deployed
behavior. The current two-stage timing contract is recorded in
[the wake-session specification](../../20/002-wake-session/spec.md); the scope
change does not itself retime that audio implementation.

This specification defines what Robine Wake means by a gentle awakening, which
mechanisms are supported by human research, and how those mechanisms should be
translated into testable product behaviour. It does not prescribe one allegedly
"scientific" volume curve: the literature does not establish one.

The extracted scientific dataset — study design, sample, intervention, outcomes,
statistics, and limitations — is maintained separately in
[evidence-review.md](evidence-review.md). That dataset is the evidentiary source;
the engineering rules in this file are explicitly downstream interpretations.

The review prioritised peer-reviewed human studies, systematic or structured
reviews, and studies comparing an intervention with a control condition. Searches
covered sleep inertia, artificial dawn, alarm acoustics, music and melody, alarm
loudness, sleep-stage alarms, snoozing, temperature, vibration, multimodal alarms,
and sensory awakening. PubMed and reference lists of the principal reviews were
used. This is an evidence map for product engineering, not a registered systematic
review, and cannot guarantee that every publication in every language was found.

## Product definition

"Gentle" has three independent outcomes. A design can improve one and worsen
another, so they must never be collapsed into a single score:

1. **Wake reliability** — the sleeper becomes behaviourally awake before the hard
   deadline.
2. **Wake experience** — the transition is perceived as comfortable and not
   startling or aversive.
3. **Post-wake function** — subjective sleepiness and objective vigilance recover
   after awakening.

The alarm must also preserve sleep before the requested wake time. An intervention
that creates repeated micro-awakenings may appear to reduce sleep inertia by
starting the awakening early while actually reducing sleep efficiency.

## Physiological model

Sleep inertia is a temporary state of hypoarousal after awakening. It can include
sleepiness, confusion, negative affect, reduced vigilance, slower responses, and a
desire to return to sleep. Brain recovery is heterogeneous rather than an immediate
global switch: sleep-like and wake-like activity can coexist during the transition.

Its severity is affected by at least:

- **circadian phase** — controlled laboratory work found cognitive sleep inertia
  substantially worse during the biological night than the biological day;
- **homeostatic sleep pressure** — sleep loss and recovery sleep can intensify it;
- **time since awakening** — different subjective and objective functions recover
  at different rates, sometimes over tens of minutes or longer;
- **sleep stage** — some studies report worse outcomes after NREM or slow-wave
  sleep while others find no independent stage effect;
- **person and context** — chronotype, sleep debt, age, health, habitual behaviour,
  and task all contribute large variability.

Robine Wake does not measure sleep stage, circadian phase, alertness or fitness
to perform a safety-critical task. An explicit button response is not proof that
sleep inertia has dissipated.

## Evidence map

Confidence describes the evidence for a consumer bedroom alarm, not the quality of
the researchers or the plausibility of the mechanism.

| Mechanism | Main finding | Confidence | Product consequence |
|---|---|---:|---|
| sufficient sleep and regular timing | sleep pressure and circadian phase strongly modulate inertia | moderate | do not promise that alarm shaping can compensate for sleep deprivation |
| 30-minute artificial dawn | several small trials improve subjective alertness; objective effects are mixed | low–moderate | best-supported future environmental feature, but optional |
| bright or blue-enriched light only after waking | results are mixed and task-dependent | low | maintain useful room light after waking; do not market blue content as a proven cure |
| melodic alarm sound | small field studies show fewer vigilance lapses and false starts | low | prefer clearly melodic, user-selected material in the gentle phase |
| rhythm or tempo alone | a 105 BPM rhythmic treatment did not outperform control | low | do not infer efficacy from BPM alone |
| preferred music | limited studies suggest benefits to comfort, sleepiness, or response speed | low | expose sound choice and learn preference; avoid one universal "best" track |
| gradual audio loudness | no controlled evidence establishes an optimal duration or curve | insufficient | treat the envelope as a product hypothesis and calibrate/test it |
| low-frequency tone or voice | wakes children and emergency-study populations more reliably than high-pitched alarms | moderate for emergency arousal; low for this product | consider for the strong fallback, not as proof of a pleasant adult awakening |
| waking in "light sleep" | stage effects are inconsistent and practical stage estimation is imperfect | insufficient | never delay the hard deadline; do not claim optimal-stage waking |
| snoozing | two small laboratory studies conflict; habitual snoozers may differ | low | make snooze explicit and measurable, not the default gentle mechanism |
| temperature manipulation | promising subjective effects in older small studies; multimodal trial was null overall | insufficient | defer until independently testable hardware exists |
| vibration | can wake sleepers and may be pleasant, but evidence targets prototypes or emergency/clinical use | low | optional secondary channel, not a replacement for the reliable audio fallback |
| odour | human olfaction does not reliably wake sleepers | moderate | exclude odour as a safety or wake-reliability mechanism |
| multimodal smart bedroom alarm | recent within-subject trial found no overall vigilance, sleepiness, or mood benefit and slightly lower sleep efficiency | low | add modalities independently and measure sleep disruption as well as benefit |

## Interpretation by mechanism

### Light before waking

Artificial-dawn studies commonly start light about 30 minutes before scheduled
waking and rise toward roughly 100–300 lux at the eye. Trials in people who report
difficulty waking have repeatedly found better subjective awakening, mood, or
alertness. Some very small studies also report better reaction time or cognitive
performance. Other trials find subjective benefits without performance or cortisol
effects, and a study in older adults found no alertness benefit while detecting more
wake before the alarm.

The likely effect is acute and may involve increased pre-wake arousal and
thermoregulation. A shift in melatonin timing and the cortisol awakening response
are not established explanations. Recent work also questions whether awakening
itself causes the previously assumed burst in cortisol secretion.

**Design rule:** if light hardware is added, the default product profile is a
30-minute dawn. Light duration must not be shortened because a non-EEG sensor
labels the user as being in light sleep. Record intervention start and explicit
pre-alarm user interactions, without inferring sleep or wake state, and allow the
intervention to be disabled.

### Sound identity

The strongest product-relevant auditory signal is preliminary evidence for melody,
not loudness shape. A small ecological experiment found fewer attention lapses and
false starts after a melodic treatment, but no significant mean reaction-time
benefit; rhythm alone did not help. The broader auditory review found too little
adult evidence for firm prescriptions, although melodic alarms and preferred music
are promising.

Emergency studies answer a different question: whether a sleeper wakes at all.
They support low-frequency signals and voice over conventional high-frequency
beeps in children and several special populations. They do not justify playing a
100 dB signal in a bedroom or claiming that the same signal reduces sleep inertia.

**Design rule:** the gentle phase should use a user-selected melodic sound with
enough spectral energy to remain audible on the installed speakers. The strong
phase optimises wake reliability and distinctness. Sound metadata such as
"melodic", "salient", and measured loudness is more useful than an unvalidated
"gentleness" label alone.

### Loudness and the missing curve evidence

Published alarm work generally compares sound type or increases test intensity to
measure an awakening threshold. The recent multimodal experiment used a two-minute
increase to 50% of an unspecified device maximum, but the combined intervention
did not improve its primary outcomes overall. This does not validate a two-minute
curve. No identified controlled study compared linear, exponential, logarithmic,
sigmoidal, or stepped bedroom-alarm envelopes, nor did one validate Robine Wake's
current five-minute linear logical-volume ramp.

ALSA mixer dB is an electrical gain setting, not sound-pressure level at the
pillow. Track mastering, amplifier gain, speaker sensitivity, distance, room
acoustics, and background noise all change the audible result. A curve expressed
only as mixer values is therefore neither transferable nor perceptually stable.

**Design rule:** replace curve-first thinking with an audible-envelope model:

- calibrate each bundled track to a common programme loudness;
- measure A-weighted level at the pillow for the actual Amp2 and speaker setup;
- store a personalised audible onset and a separately bounded maximum;
- specify changes in dB, not arbitrary 0–100 percentage points;
- use monotonic, click-free transitions and never exceed the hardware safety cap;
- escalate on elapsed non-response and observed wake behaviour, not because a
  mathematically smooth curve happens to end.

## Robine Wake hypotheses

The published data constrain the design but do not determine it. Robine Wake
therefore adopts the following original hypotheses as product decisions. They are
not presented as findings from the cited papers.

### H1 — Gentleness is controlled arousal, not continuous quietness

An alarm that remains below the sleeper's audible threshold for several minutes is
not gentle; it is absent, followed by a late surprise. Startle is more likely to be
related to the level and rate of change when the signal becomes perceptible than to
the total mathematical duration of a mixer ramp.

Robine Wake shall cross the likely audibility threshold deliberately in the first
seconds, with a bounded slope, then give the brain time to orient before adding more
level.

### H2 — Stable melody supports orientation

The auditory system needs a stable object to recognise. Continually changing gain
for five minutes makes both the sound and its meaning unstable. A melodic plateau
after fade-in should provide a less confusing transition than an uninterrupted
ramp while preserving the preliminary vigilance benefit associated with melody.

### H3 — Salience steps are better than imperceptible micro-increments

One-second mixer changes are operationally smooth but most are not meaningful to a
sleeper. Discrete 3 dB steps, separated by stable periods, should renew attention
without the abruptness of switching immediately to the strong alarm. The 3 dB value
is a psychoacoustic engineering choice, not an outcome from an alarm trial.

### H4 — Failure is behavioural, not volumetric

For this camera-free product, absence of response means no authorized explicit
snooze or dismissal before the deadline. Elapsed non-response triggers the strong
fallback. No movement, occupancy or inferred sleep state can pause escalation;
reaching the tactile ceiling cannot change the audio deadline.

### H5 — The fallback changes meaning before maximising level

A novel, salient sound should regain attention more efficiently than making the
same familiar track progressively louder. The strong phase therefore changes sound
identity and spectral character, then uses a higher but bounded level. It is not the
last point of the gentle curve.

### H6 — The bedroom, not the mixer, defines loudness

Raw ALSA dB does not describe the pressure reaching the pillow. Background noise,
track mastering, speaker sensitivity, placement, distance, and room reflections all
matter. Robine Wake's target is an acoustic level at the pillow; the Amp2 mixer is
only the actuator used to reach it.

### H7 — Light prepares; sound declares

Future visible-light hardware should begin a slow environmental transition before
the requested time. Audio remains the unambiguous declaration that wake time has
arrived. Visible-light and tactile preparation remain independently configurable.

## Calibrated Robine Wake envelope — design target

This is the proposed calibrated profile derived from the hypotheses above. Its
implementation and acoustic acceptance remain separate from the camera-removal
and tactile work; current timing remains defined by `20-002` until that profile
is implemented. The table below must not be combined with the current pre-wake
ramp and five-minute plateau as though they were one timeline.

Let:

- `B` be the A-weighted background level measured near the pillow;
- `L_gentle = clamp(B + 10 dB, 42 dBA, 52 dBA)`;
- `L_strong = clamp(max(L_gentle + 12 dB, 62 dBA), 62 dBA, 72 dBA)`;
- `S(u) = 3u² - 2u³`, the smoothstep function for `0 ≤ u ≤ 1`;
- `G(L)` be the calibrated Amp2 mixer gain required to produce acoustic level `L`.

Until physical SPL calibration exists, the implementation may approximate the
relative changes in mixer dB, but the UI must not label those values as dBA.

| Time from scheduled wake | State | Output |
|---:|---|---|
| 0–12 s | `gentle_fade` | gentle track rises from `L_gentle − 18 dB` to `L_gentle` using `S(t/12)` in the dB domain |
| 12–72 s | `gentle_hold` | hold the melodic track at `L_gentle` |
| 72 s | `gentle_step_1` | increase to `min(L_gentle + 3 dB, L_strong − 3 dB)` |
| 102 s | `gentle_step_2` | increase to `min(L_gentle + 6 dB, L_strong − 3 dB)` |
| 132 s | `gentle_step_3` | increase to `min(L_gentle + 9 dB, L_strong − 3 dB)` |
| 162–166 s | `strong_crossfade` | crossfade over 4 s to `strong_sound_id` and `L_strong` |
| after 166 s | `strong_hold` | loop the strong sound at `L_strong` until dismissal, snooze, or safety timeout |

The fade is S-shaped in **acoustic dB**, not in the 0–100 UI value and not in raw
PCM amplitude. This gives zero slope at both ends, avoids a click or sudden change
of derivative, and reaches a useful level quickly. The later progression is stepped
because the product is trying to renew salience, not draw an aesthetically smooth
graph.

### Explicit response only

Only an authorized snooze or dismissal interrupts the escalation timeline.
No movement-based extension exists. In the proposed calibrated profile, the
strong crossfade therefore starts at 162 seconds with no former 60-second
extension. For the current implementation, retain the deadline in `20-002`.
Tactile output follows the same session clock and never postpones either deadline.

### Track preparation

Bundled gentle tracks should be normalised to approximately `−16 LUFS-I` with a
true-peak ceiling of `−1 dBTP`. Strong tracks should use the same loudness reference
so that the acoustic transition is controlled by the envelope rather than arbitrary
mastering differences. These are production hypotheses chosen for consistency,
not clinical thresholds.

### Timing and sleep-stage alarms

Sleep stage is scored clinically from signals such as EEG, eye movement, and muscle
tone. Consumer and contactless devices are generally much better at recognising
sleep than wake and show inconsistent stage classification. One published smart
alarm predictor reported only 66–70% four-class accuracy and did not establish a
clinically meaningful improvement in morning function.

Robine Wake has no camera or presence sensor and must not label N1, N2, N3 or
REM. Any prelude is determined by explicit user settings and time, never an
inferred sleep stage or detected movement.

### Snooze

A 2022 pilot with ten participants suggested snoozing extended light sleep near
waking and could prolong inertia. A later within-subject study of 31 habitual
snoozers found that 30 minutes of snoozing improved or did not affect immediate
cognitive performance, lost about six minutes of sleep, and produced no clear
sleepiness, mood, cortisol, or architecture effect. The samples and populations do
not support one universal policy.

**Design rule:** retain an explicit snooze limit, record the number and total sleep
fragmentation, and let habitual snoozers compare snooze-enabled and direct-wake
profiles. Never describe snoozing as proven beneficial or harmful for everyone.

### Confirmation versus alertness

Record explicit snooze and authorized dismissal as user interactions. The system
does not confirm bed exit or cognitive alertness. A physical response acknowledges
the alarm, without proving that sleep inertia has ended.

## Evidence-informed wake sequence

```text
optional light prelude
        |
scheduled audio + optional progressive vibration
        |
        +-- authorized physical dismissal --> stop outputs
        +-- authorized snooze --> silence outputs --> restart
        +-- no explicit response --> strong audio at its fixed deadline
                                      |
                                      +--> dismissal / snooze / safety timeout
```

The vibration mode is defined in
[bed vibration](../../30/004-bed-vibration/spec.md). Its failure does not suppress
or delay the audible fallback. No presence signal participates in this sequence.

## Product diagnostics

Each wake session should eventually support the following privacy-preserving event
data, without collecting images or presence observations:

- scheduled time, actual audio onset, and audio-start latency;
- envelope segment, sound ID, normalised track loudness, mixer dB, and calibration
  profile identifier for every transition;
- explicit interaction, snooze, escalation, dismissal and timeout;
- tactile mode, calibrated intensity, limiter/cutoff events and failures;
- minutes of any pre-wake intervention and explicit pre-alarm interactions;
- the configured acoustic calibration and the fallback deadline applied.

Raw camera frames, inferred medical conditions, and definitive sleep-stage labels
remain out of scope.

## Commissioning constraints

Commissioning is a hardware verification step, not a human-subject experiment. It
must confirm that both installed speakers reproduce the requested levels at the
pillow position, that transitions are click-free, that the limiter prevents output
above 72 dBA under the calibration track, and that the strong fallback still starts
on time with the tactile output disconnected or failed.

## Requirements

- `GWA-001` — Product language shall distinguish wake reliability, wake experience,
  and post-wake function.
- `GWA-002` — No audio curve shall be described as evidence-based without a direct
  controlled comparison supporting that curve.
- `GWA-003` — Audio envelopes shall be defined in calibrated dB transitions rather
  than raw mixer percentages alone.
- `GWA-004` — The strong fallback deadline shall be independent of sleep-stage
  inference and tactile availability.
- `GWA-005` — Retired: interpretation of infrared observations.
- `GWA-006` — Retired: interpretation of detected bed exit.
- `GWA-007` — Planned calibrated audio profile: implement the fade–hold–step–fallback
  envelope after its separate implementation and acoustic validation; current
  runtime timing is specified by `20-002`.
- `GWA-008` — Any light prelude shall be user-controlled and shall not move the hard
  wake deadline.
- `GWA-009` — Retired: movement-based escalation extension is removed.
- `GWA-010` — The interface shall label research-derived facts separately from
  hypothesis-driven product settings.

- `GWA-011` — Only authorized explicit interactions shall interrupt escalation;
  no presence or movement signal shall delay the selected strong deadline.
- `GWA-012` — User acknowledgement shall not be presented as proof of bed exit
  or recovered cognitive alertness.

## Research references

### Sleep inertia and its modifiers

1. Ruby PM et al. *From physiological awakening to pathological sleep inertia.*
   Neurophysiol Clin. 2024. [doi:10.1016/j.neucli.2023.102934](https://doi.org/10.1016/j.neucli.2023.102934)
2. Jewett ME et al. *Time course of sleep inertia dissipation in human
   performance and alertness.* J Sleep Res. 1999.
   [PubMed 10188130](https://pubmed.ncbi.nlm.nih.gov/10188130/)
3. Scheer FAJL et al. *An endogenous circadian rhythm in sleep inertia results in
   greatest cognitive impairment upon awakening during the biological night.* J
   Biol Rhythms. 2008.
   [doi:10.1177/0748730408318081](https://doi.org/10.1177/0748730408318081)
4. Silva EJ, Duffy JF. *Sleep inertia varies with circadian phase and sleep stage
   in older adults.* Behav Neurosci. 2008.
   [doi:10.1037/0735-7044.122.4.928](https://doi.org/10.1037/0735-7044.122.4.928)
5. Gorgoni M et al. *Sleep inertia and sleep homeostatic processes: measurement
   of electroencephalographic awakening reaction and task performance.* J Sleep
   Res. 2015. [PubMed 26004680](https://pubmed.ncbi.nlm.nih.gov/26004680/)
6. Hilditch CJ, Dorrian J, Banks S. *Time to wake up: reactive countermeasures to
   sleep inertia.* Ind Health. 2016.
   [doi:10.2486/indhealth.2015-0236](https://doi.org/10.2486/indhealth.2015-0236)
7. Chen S et al. *Thalamic dynamics orchestrate the recovery of tonic alertness
   during nocturnal sleep inertia.* Commun Biol. 2026.
   [PubMed 41832350](https://pubmed.ncbi.nlm.nih.gov/41832350/)

### Light and artificial dawn

8. Thorn L et al. *The effect of dawn simulation on the cortisol response to
   awakening in healthy participants.* Psychoneuroendocrinology. 2004.
   [doi:10.1016/j.psyneuen.2003.08.005](https://doi.org/10.1016/j.psyneuen.2003.08.005)
9. Giménez MC et al. *Effects of artificial dawn on subjective ratings of sleep
   inertia and dim light melatonin onset.* Chronobiol Int. 2010.
   [doi:10.3109/07420528.2010.496912](https://doi.org/10.3109/07420528.2010.496912)
10. van de Werken M et al. *Effects of artificial dawn on sleep inertia, skin
    temperature, and the awakening cortisol response.* J Sleep Res. 2010.
    [doi:10.1111/j.1365-2869.2010.00828.x](https://doi.org/10.1111/j.1365-2869.2010.00828.x)
11. Thompson A et al. *Improving the health of office workers: effects of
    artificial dawn on morning physiology and performance.* Eur J Appl Physiol.
    2014. [doi:10.1007/s00421-014-2831-z](https://doi.org/10.1007/s00421-014-2831-z)
12. Santhi N et al. *Morning sleep inertia in alertness and performance: effect of
    cognitive domain and white light conditions.* PLoS One. 2013.
    [PubMed 24260280](https://pubmed.ncbi.nlm.nih.gov/24260280/)
13. Hilditch CJ et al. *Rise and shine: the use of polychromatic short-wavelength-
    enriched light to mitigate sleep inertia at night following awakening from
    slow-wave sleep.* J Sleep Res. 2022.
    [doi:10.1111/jsr.13558](https://doi.org/10.1111/jsr.13558)
14. Gabel V et al. *Effect of artificial dawn light on cardiovascular function,
    alertness, and balance in middle-aged and older adults.* Sleep. 2020.
    [doi:10.1093/sleep/zsaa082](https://doi.org/10.1093/sleep/zsaa082)
15. Norden MJ, Avery DH. *A controlled study of dawn simulation in subsyndromal
    winter depression.* Acta Psychiatr Scand. 1993.
    [doi:10.1111/j.1600-0447.1993.tb03415.x](https://doi.org/10.1111/j.1600-0447.1993.tb03415.x)
16. Zhu YY et al. *Effects of artificial dawn on sleep inertia in alertness,
    mood, and cognitive performance in healthy participants.* Sleep. 2018
    conference abstract. [doi:10.1093/sleep/zsy061.209](https://doi.org/10.1093/sleep/zsy061.209)
17. Bowles NP et al. *Awakening not associated with an increased rate of cortisol
    secretion.* Proc R Soc B. 2025.
    [PMC 11732391](https://pmc.ncbi.nlm.nih.gov/articles/PMC11732391/)

### Sound, alarm signals, and vibration

18. McFarlane SJ et al. *Alarm tones, voice warnings, and musical treatments: a
    systematic review of auditory countermeasures for sleep inertia in abrupt and
    casual awakenings.* Clocks Sleep. 2020.
    [doi:10.3390/clockssleep2040031](https://doi.org/10.3390/clockssleep2040031)
19. McFarlane SJ et al. *Auditory countermeasures for sleep inertia: exploring the
    effect of melody and rhythm in an ecological context.* Clocks Sleep. 2020.
    [doi:10.3390/clockssleep2020017](https://doi.org/10.3390/clockssleep2020017)
20. McFarlane SJ et al. *Alarm tones, music and their elements: analysis of
    reported waking sounds to counteract sleep inertia.* PLoS One. 2020.
    [PubMed 31990906](https://pubmed.ncbi.nlm.nih.gov/31990906/)
21. Bruck D et al. *How does the pitch and pattern of a signal affect auditory
    arousal thresholds?* J Sleep Res. 2009.
    [doi:10.1111/j.1365-2869.2008.00710.x](https://doi.org/10.1111/j.1365-2869.2008.00710.x)
22. Smith GA et al. *Comparison of the effectiveness of female voice, male voice,
    and hybrid voice-tone smoke alarms for sleeping children.* Acad Pediatr.
    2019. [doi:10.1016/j.acap.2019.06.016](https://doi.org/10.1016/j.acap.2019.06.016)
23. Bruck D, Thomas IR. *Smoke alarms for sleeping adults who are hard-of-hearing:
    comparison of auditory, visual, and tactile signals.* Ear Hear. 2009.
    [doi:10.1097/AUD.0b013e3181906f89](https://doi.org/10.1097/AUD.0b013e3181906f89)
24. Korres G et al. *A vibrotactile alarm system for pleasant awakening.* IEEE
    Trans Haptics. 2018.
    [doi:10.1109/TOH.2018.2804952](https://doi.org/10.1109/TOH.2018.2804952)
25. Attali V et al. *Awakening efficacy of a vibrotactile device in patients on
    home nocturnal ventilatory assistance and healthy subjects as family caregiver
    proxies.* Chron Respir Dis. 2021.
    [doi:10.1177/1479973120983331](https://doi.org/10.1177/1479973120983331)

### Smart alarms, snooze, and multimodal interventions

26. Slyusarenko K, Fedorin I. *Smart alarm based on sleep stages prediction.*
    EMBC. 2020.
    [doi:10.1109/EMBC44109.2020.9176320](https://doi.org/10.1109/EMBC44109.2020.9176320)
27. Campanella A et al. *The efficacy of a multimodal bedroom-based "smart" alarm
    system on mitigating the effects of sleep inertia.* Clocks Sleep. 2024.
    [doi:10.3390/clockssleep6010013](https://doi.org/10.3390/clockssleep6010013)
28. Tsutsui K et al. *Effects of using a snooze alarm on sleep inertia after
    morning awakening.* J Physiol Anthropol. 2022.
    [PMC 9804954](https://pmc.ncbi.nlm.nih.gov/articles/PMC9804954/)
29. Sundelin T et al. *Is snoozing losing? Why intermittent morning alarms are
    used and how they affect sleep, cognition, cortisol, and mood.* J Sleep Res.
    2024. [doi:10.1111/jsr.14054](https://doi.org/10.1111/jsr.14054)
30. Lee YJ et al. *Performance of consumer wrist-worn sleep tracking devices
    compared to polysomnography: a meta-analysis.* J Clin Sleep Med. 2025.
    [doi:10.5664/jcsm.11460](https://doi.org/10.5664/jcsm.11460)
31. Chinoy ED et al. *Performance of seven consumer sleep-tracking devices
    compared with polysomnography.* Sleep. 2021.
    [PubMed 33378539](https://pubmed.ncbi.nlm.nih.gov/33378539/)
32. Carskadon MA, Herz RS. *Minimal olfactory perception during sleep: why odor
    alarms will not work for humans.* Sleep. 2004.
    [PubMed 15164891](https://pubmed.ncbi.nlm.nih.gov/15164891/)
