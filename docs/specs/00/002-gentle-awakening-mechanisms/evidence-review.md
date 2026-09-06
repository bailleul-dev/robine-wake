# Scientific Evidence Review — Awakening and Sleep Inertia

Product scope note (2026-09-06): camera and bed-presence features are removed.
Camera-related observations below are research context, not active hardware
requirements. This scope update does not constitute a new literature review.

## Review question

Which measured physiological factors and controlled interventions affect:

1. the probability or latency of awakening;
2. subjective sleep inertia after awakening; and
3. objective cognitive performance after awakening?

These outcomes are analysed separately. A stimulus can wake someone reliably
without improving subsequent cognition, and a pleasant stimulus can fail to wake a
deep sleeper.

Search date: 2026-08-20. Sources were peer-reviewed human studies indexed in
PubMed, full texts from PubMed Central/Europe PMC, and the reference lists of the
two principal structured reviews. Search concepts included `sleep inertia`,
`awakening`, `alarm`, `auditory`, `melody`, `music`, `volume`, `artificial dawn`,
`light`, `temperature`, `snooze`, `vibrotactile`, `sleep stage`, and `smart alarm`.
Marketing pages and unvalidated commercial claims were excluded.

This is a structured evidence review for engineering, not a preregistered PRISMA
systematic review. Absence of a study in this table does not prove absence from all
databases. Numeric values below are reported values, not values reconstructed from
figures.

## Directly measured determinants of sleep inertia

| Study | Design and sample | Measurement | Quantitative result | What it establishes |
|---|---|---|---|---|
| Jewett et al., 1999 | three consecutive mornings after 8 h sleep; habitual wake time; constant-routine and ordinary morning conditions | subjective alertness and cognitive-throughput task for 4 h | exponential time constant: **0.67 h** subjective alertness and **1.17 h** cognitive performance; near-asymptotic recovery **2–4 h** | recovery is outcome-dependent and is not an instantaneous on/off event; ordinary breakfast, shower, posture, and ~150 lux room light did not remove it |
| Scheer et al., 2008 | forced-desynchrony laboratory protocol; **n=12**; repeated awakenings, initially analysed from stage N2 | correct additions during first 20 min awake | impairment was **3.6 times larger** during biological night than biological day; circadian effect **p=.007** for stage-N2 awakenings and **p=.004** with all stages | circadian phase has a strong effect independent of measured sleep stage and sleep drive |
| Gorgoni et al., 2015 | recovery sleep after **40 h awake** versus baseline sleep | EEG during awakening plus performance | higher sleep pressure produced stronger inertia and persistent sleep EEG features; no independent awakening-stage effect detected | sleep debt/homeostatic pressure matters; stage alone is not a sufficient predictor |
| Chen et al., 2026 | repeated nocturnal awakenings with simultaneous EEG-fMRI; **n=26** | PVT and brain activation/connectivity | cingulo-opercular/thalamic activation was lowest on waking and increased with time awake; thalamic recovery mediated PVT recovery | supports a gradual, regionally heterogeneous neural transition rather than a binary wake switch |

### Interpretation limits

- Reported duration depends on task, baseline, circadian phase, and statistical
  definition. “Sleep inertia lasts X minutes” is not a universal constant.
- Sleep-stage findings conflict across controlled studies. Circadian phase and sleep
  pressure can be stronger determinants.
- A camera-derived movement signal cannot measure the EEG/fMRI processes above.

## Controlled light and artificial-dawn studies

| Study | Design and sample | Intervention and control | Outcomes | Reported data | Limitations |
|---|---|---|---|---|---|
| Thorn et al., 2004 | counterbalanced, four weekdays; **n=12** | artificial dawn rising to ~**250 lux over 30 min** vs no dawn | salivary cortisol at 0/15/30/45 min; self-reported arousal | first-45-min cortisol output **12.8% higher**; arousal **z=2.608** and significant | very small sample; cortisol is a surrogate, not wake reliability or cognition |
| Giménez et al., 2010 | two home crossover studies; each condition lasted two weeks | **0, 50, 250 lux** dawn in study 1; 0 vs self-selected dawn in study 2 | subjective sleep-inertia complaints; dim-light melatonin onset | dawn significantly reduced complaints in both studies; no significant melatonin-onset shift at 50 or 250 lux | subjective primary outcome; abstract does not provide effect magnitude |
| van de Werken et al., 2010 | random-order control/dawn nights; **n=16**, 8 women, age **22.8±4.6**; participants needed ≥60 min to feel fully awake | light during final **30 min** of sleep vs light switched on at wake | sleepiness, activation, addition, RT, EEG, core/skin temperature, cortisol at 1–90 min | less subjective sleepiness and more activation; faster distal-skin-temperature-gradient decline; **no significant performance, core-temperature, or cortisol effect** | small selected sample; subjective and objective results diverged |
| Thompson et al., 2014 | randomised-order crossover; **n=8** adults reporting difficulty waking | 30-min artificial dawn vs control | alertness, sleep quality, reaction time, additions, physical time trial | better perceived sleep quality and alertness; more additions; RT approximately **0.81 s vs 0.86 s**; physical-performance difference was a trend | extremely small sample and multiple outcomes |
| Santhi et al., 2013 | four-condition crossover after 6.5 h sleep; **n=11** | 19 lux dim, 200 lux conventional, 195 lux blue-enhanced, **750 lux** bright blue-enhanced white light for 4 h after wake | KSS, PVT, addition, 1-/3-back | all domains impaired immediately (**p<.01**); most light-by-time tests were null; limited 3-back-specific effects | tests light after awakening, not dawn; 44 awakenings included mixed stages |
| Hilditch et al., 2022 | randomised within-subject crossover; **n=12**, PVT **n=11**; after a 5 h sleep-restriction night and awakening from confirmed SWS | **242.77 lux**, 338.03 melanopic EDI lux, peak 456 nm for ~1 h vs 0.26 lux red control | 5-min PVT at +2/+17/+32/+47 min, KSS, mood | fewer PVT lapses: **χ²(1)=5.285, p=.022, marginal R²=.265**; PVT speed null: **F(1,70)=1.984, p=.163**; KSS **p=.029**, alert VAS **p=.005**, cheerful VAS **p=.004** | nocturnal SWS awakenings in a tiny young sample; not a normal morning alarm |
| Gabel et al., 2020 | crossover artificial dawn in middle-aged/older adults; **n=23**, age **67.3±8.8 y** | 30-min dawn vs control | sleep, cardiovascular markers, subjective/objective alertness, balance, cortisol | **33% less sleep** before scheduled wake; BP **6.24 mmHg lower**, HR **0.93 bpm higher**; no significant alertness, balance, or cortisol benefit | population-specific; demonstrates possible sleep disruption |
| Campanella et al., 2024 | counterbalanced within-subject, four laboratory nights; **37 recruited, 29 analysed** | temperature +3°F from -45 min; sleep-sensor-triggered sigmoidal light 0→**300 lux**, ~4000 K, over 15–30 min; shades -3 min; nature/music audio ramp -2 min to 50%; vs 50% beeping alarm | PVT, Stanford Sleepiness Scale, PANAS at +5/+15/+30/+60/+90 min; commercial mattress sensor sleep metrics | **no condition effect** on any PVT metric, sleepiness, or mood; sleep efficiency **86.65±5.93% control vs 83.97±10.18% intervention, p=.042**; WASO **52.42±41.98 vs 64.79±60.76 min, p=.065** | multimodal components cannot be separated; light-sleep detector sensitivity .57 and specificity .69; subgroup interactions are exploratory |

### Light synthesis

- A 30-minute pre-wake dawn has repeated but mostly **subjective** positive results.
- Objective performance effects are inconsistent. The most convincing positive PVT
  result used post-wake short-wavelength-enriched light after nocturnal SWS, not an
  ordinary morning dawn.
- Lux, spectrum, timing, prior sleep, circadian phase, and outcome are not
  interchangeable. There is no single validated “light curve.”
- Cortisol is not an accepted proxy for successful gentle awakening. The proposed
  awakening-triggered secretion mechanism has recently been challenged directly.

## Controlled auditory studies

| Study | Design and sample | Stimuli | Objective results | Scientific limitation |
|---|---|---|---|---|
| McFarlane et al., 2020 melody experiment | ecological, paired sessions; melodic arm **n=10**; control always first, treatment next day | matched 105 BPM control vs melodic alarm; participant device/level; rising-volume feature disabled | RT **504.21±107.02 vs 475.84±84.43 ms, p=.184, d=.455**; lapses **24.20±18.29 vs 19.40±17.10, p=.016, d=.930**; false starts **2.20±1.69 vs 1.00±1.05, p=.001, d=1.521**; PVT score **.56±.30 vs .66±.28, p=.006, d=−1.121** | tiny group, no counterbalanced order, remote devices and sound pressure uncontrolled, several tests without multiplicity correction |
| McFarlane et al., 2020 rhythm arm | same protocol; rhythm arm **n=10** | matched control vs rhythm-only alarm, 105 BPM | no significant result: RT **p=.193**, lapses **p=.609**, false starts **p=.194**, score **p=.683** | does not show that 105 BPM or rhythm alone is effective |
| Tassi et al., cited by auditory review | controlled nap study | **75 dB pink noise** vs control following a 1 h nap | review reports reduction/elimination of observed sleep-inertia effects | intense post-nap noise is not a pleasant morning alarm; original outcome must be consulted before parameter use |
| Hayashi et al., cited by auditory review | controlled short-nap study | participant-preferred excitatory popular music at **60 dB** among countermeasures | review reports improvement in reaction time, subjective sleepiness, and comfort for high-preference music | nap context; preference and excitation are confounded; not a volume-envelope comparison |
| Bruck et al., 2009 | laboratory arousal-threshold study; **n=39** young adults; stage-4 sleep | different pitch/pattern signals | 400/520 Hz square-wave signals required lower awakening levels than high-frequency signals; a silence interval showed a favourable trend | measures emergency awakening threshold, not pleasantness or post-wake inertia |
| Bruck & Thomas, 2009 | **n=38** adults with mild-to-moderately-severe hearing loss, slow-wave sleep | 520 Hz square wave, 3100 Hz alarm, bed/pillow shaker, strobe | at **75 dBA**, 520 Hz woke **92%**, high-pitch alarm **56%**; shakers **80–84%** at sold intensity; strobe **27%** | special population and emergency-signal endpoint |
| McFarlane et al., 2020 systematic review | 341 records screened; **12 studies included** | alarm tones, voice, music | low pitch/voice consistently useful for children or emergency waking; adult abrupt-wake evidence insufficient; melodic/preferred music promising in non-emergency adults | heterogeneous populations, endpoints, levels, and protocols prevent one acoustic prescription |

### What the auditory data do not contain

No located controlled human study compares:

- linear versus exponential versus logarithmic versus sigmoidal audio ramps;
- a 30-second versus 2-minute versus 5-minute ramp while controlling sound and
  sound pressure;
- mixer percentage as a predictor of sound-pressure level at the pillow; or
- the exact moment at which a gentle track should switch to a strong track.

The two-minute audio ramp in Campanella et al. is one component of a null overall
multimodal intervention and cannot validate that duration or shape. Consequently,
Robine Wake's existing five-minute linear ramp is an **untested implementation
choice**, not scientific data.

## Sleep-stage targeting and sensor validity

| Study | Dataset and reference | Result | Consequence for interpretation |
|---|---|---|---|
| Slyusarenko & Fedorin, 2020 | **138 nights, 92 people**; sleep-stage prediction | four-class accuracy **66–70%**; two-class accuracy **71–77%** | prediction accuracy alone does not demonstrate better wake experience or performance |
| Chinoy et al., 2021 | **n=34**, seven consumer devices vs polysomnography | sleep sensitivity ≥**.93**, wake specificity **.18–.54**; sleep-stage comparisons mixed | devices tend to call quiet wakefulness sleep and stage outputs are inconsistent |
| Lee et al., 2025 meta-analysis | **24 studies, 798 participants**, wrist devices vs polysomnography | mean difference: total sleep time **−16.854 min** (95% CI −26.332 to −7.375), sleep efficiency **−4.691 points** (−7.079 to −2.302), sleep latency **+2.574 min** (.606 to 4.542), WASO **+13.255 min** (4.522 to 21.988) | aggregate sleep metrics differ significantly from PSG; stage-triggered product decisions require direct validation |
| Campanella et al., 2024 sensor | EarlySense commercial mattress sensor vs cited PSG validation | sleep sensitivity **.96**, specificity **.49**; light-sleep sensitivity **.57**, specificity **.69** | its trigger often cannot identify light sleep reliably; a shorter stage-triggered dawn did not produce a robust overall benefit |

Polysomnographic sleep stage is not recoverable from an ordinary infrared camera
without a separately validated model and reference-PSG study. Even a correct stage
label would not remove circadian phase, sleep pressure, or individual variability.

## Snooze data: conflicting experiments

| Study | Protocol | Sleep results | Post-wake results | Limitation |
|---|---|---|---|---|
| Tsutsui et al., 2022 | crossover laboratory study, **n=10**; four 50 dB alarms every 5 min during final 20 min; final 60 dB beep | total sleep **387.8±7.8 vs 396.5±7.8 min, p=.021**; last-20-min sleep **15.7±.9 vs 19.7±.2 min, p=.002**; awakenings **4.1±.77 vs .3±.21, p<.001**; transitions **12.2±2.0 vs 3.5±.92, p=.006** | RT condition main effect null (**p=.15**), but final session slower **238.4±9.6 vs 221.9±7.9 ms, p=.024**; global-vigour interaction **p=.006** | extremely small sample; multiple comparisons; no N3 in final 20 min |
| Sundelin et al., 2024 | survey **n=1732** plus within-subject PSG laboratory study of habitual snoozers **n=31**; 30-min snooze vs abrupt wake | approximately **6 min less sleep** with snooze; prevented awakening from N3; no clear overall architecture effect | cognition immediately after rising improved or was unchanged; no clear sleepiness, mood, or cortisol effect | selected habitual snoozers; abstract reports Bayes factors of varying strength |

The experiments differ in participant selection, snooze duration, tones, and task
timing. Their disagreement is scientific evidence against a universal snooze claim.

## Other sensory mechanisms

| Mechanism | Study and sample | Result | Interpretation |
|---|---|---|---|
| vibration | Korres et al., 2018, two prototype experiments | continuous vibrotactile modulation rated most pleasant while remaining perceptible/arousing | preliminary user-experience evidence; adaptive stage trigger was not established as a clinical benefit |
| vibration reliability | Attali et al., 2021; healthy **n=20**, central hypoventilation **n=8**, COPD **n=9** | cognitive awakening on **94%** of alarms in healthy participants, **66%** CH, **63%** COPD; all five alarms produced cognitive awakening in **72%**, **37.5%**, **33%** respectively | useful secondary modality, but not universally reliable |
| olfaction | Carskadon & Herz, 2004; **n=6**, PSG | peppermint ineffective in N2/N4/REM; pyridine response **45% N2**, **0% N4**, about **33% REM**; 800 Hz tone effective on ≥**75%** of trials | odour is not a reliable wake alarm |
| combined vibration + audio | clinical trial, **n=10** normal sleepers | response frequency increased with stimulus intensity; combined vibration+audio caused more frequent/intense NREM arousals than audio alone | supports multimodal arousal probability, not reduced sleep inertia or pleasantness |

## Strength-of-evidence conclusion

| Claim | Assessment |
|---|---|
| sleep inertia is real and multi-dimensional | strong |
| circadian phase and sleep pressure influence severity | moderate to strong |
| a 30-minute artificial dawn improves subjective morning experience in some people | low to moderate |
| dawn reliably improves objective cognitive performance | low and inconsistent |
| melodic/preferred audio improves some post-wake vigilance measures | low, promising |
| one tempo, frequency, loudness, or ramp is optimal for gentle adult waking | unsupported |
| movement-only sleep-stage targeting improves waking | unsupported |
| snoozing is universally beneficial or harmful | unsupported/conflicting |
| a multimodal gradual bedroom alarm is superior to a standard alarm | not demonstrated by the 2024 controlled trial |

The literature therefore constrains but does not select Robine Wake's audio curve.
The project makes its own explicit mechanistic hypotheses in `spec.md`, chooses one
deterministic product envelope, and does not mislabel that envelope as a published
scientific result. Mapping ALSA percentages alone cannot be described as acoustic
or physiological data.

## Primary sources

- [Ruby et al., 2024 — physiological awakening and pathological sleep inertia](https://doi.org/10.1016/j.neucli.2023.102934)
- [Jewett et al., 1999 — time course](https://doi.org/10.1111/j.1365-2869.1999.00128.x)
- [Scheer et al., 2008 — circadian phase](https://doi.org/10.1177/0748730408318081)
- [Gorgoni et al., 2015 — homeostatic pressure](https://pubmed.ncbi.nlm.nih.gov/26004680/)
- [Chen et al., 2026 — thalamic dynamics](https://pubmed.ncbi.nlm.nih.gov/41832350/)
- [Thorn et al., 2004 — dawn and cortisol](https://doi.org/10.1016/j.psyneuen.2003.08.005)
- [Giménez et al., 2010 — dawn and subjective inertia](https://doi.org/10.3109/07420528.2010.496912)
- [van de Werken et al., 2010 — dawn, performance, temperature, cortisol](https://doi.org/10.1111/j.1365-2869.2010.00828.x)
- [Thompson et al., 2014 — dawn and performance](https://doi.org/10.1007/s00421-014-2831-z)
- [Santhi et al., 2013 — morning light conditions](https://pubmed.ncbi.nlm.nih.gov/24260280/)
- [Hilditch et al., 2022 — nocturnal post-wake light](https://doi.org/10.1111/jsr.13558)
- [Gabel et al., 2020 — artificial dawn in older adults](https://doi.org/10.1093/sleep/zsaa082)
- [McFarlane et al., 2020 — auditory systematic review](https://doi.org/10.3390/clockssleep2040031)
- [McFarlane et al., 2020 — melody and rhythm experiment](https://doi.org/10.3390/clockssleep2020017)
- [Bruck et al., 2009 — pitch and pattern](https://doi.org/10.1111/j.1365-2869.2008.00710.x)
- [Bruck & Thomas, 2009 — auditory/tactile/visual emergency waking](https://doi.org/10.1097/AUD.0b013e3181906f89)
- [Slyusarenko & Fedorin, 2020 — sleep-stage prediction](https://doi.org/10.1109/EMBC44109.2020.9176320)
- [Chinoy et al., 2021 — seven consumer trackers vs PSG](https://pubmed.ncbi.nlm.nih.gov/33378539/)
- [Lee et al., 2025 — consumer tracker meta-analysis](https://doi.org/10.5664/jcsm.11460)
- [Campanella et al., 2024 — multimodal smart alarm](https://doi.org/10.3390/clockssleep6010013)
- [Tsutsui et al., 2022 — snooze experiment](https://pmc.ncbi.nlm.nih.gov/articles/PMC9804954/)
- [Sundelin et al., 2024 — habitual snoozers](https://doi.org/10.1111/jsr.14054)
- [Korres et al., 2018 — vibrotactile pleasant awakening](https://doi.org/10.1109/TOH.2018.2804952)
- [Attali et al., 2021 — vibrotactile awakening efficacy](https://doi.org/10.1177/1479973120983331)
- [Carskadon & Herz, 2004 — olfactory awakening](https://pubmed.ncbi.nlm.nih.gov/15164891/)
