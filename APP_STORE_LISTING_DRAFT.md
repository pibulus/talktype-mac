# TalkType — Mac App Store listing draft

This is listing copy and a product-page plan. The app ships as a **paid download**: one price, no trial, no StoreKit, no subscription. Anything below that promises a trial or an unlock is a bug in this file.

## Positioning

A little ghost in the menu bar that turns speech into text you can use right away.

## English (US)

**Name**

TalkType: Voice to Text

**Subtitle**

Say it messy. Get it clean.

**Promotional text**

Meet the little ghost in your Mac’s menu bar. Say what you mean, get words you can use.

**Description**

> Do not paste this section into App Store Connect as written. It promises a
> 50-dictation trial and a lifetime unlock; the build has no StoreKit and no
> counter, so submitting it would be a guideline 2.3.1 / 3.1.1 rejection.
> Ship the copy only after the paywall exists, or cut the trial sentence.

Meet the little ghost in your Mac’s menu bar. TalkType turns spoken thoughts into text you can copy into the app you’re using.

Tap to start, speak naturally, and keep recent transcripts close at hand. Add names and phrases to custom vocabulary to help recognition get them right.

- Dictation from the menu bar
- English and Spanish
- Custom vocabulary for names and phrases
- Recent transcripts you can copy or delete
- Optional Deepgram live transcription
- Optional Gemini text polish

One purchase, no account, no subscription. Optional cloud engines use your own API keys.

Optional cloud engines use your own API keys; provider terms and usage charges may apply.

**Keywords**

dictation,voice to text,speech to text,transcribe,voice typing,notes,memo,microphone,writing

## Purchase plan (decided)

- **Paid app, one price.** No trial, no in-app purchase, no StoreKit, nothing to restore.
- Price: **US$29.99** (App Store Connect auto-sets the AU storefront, roughly A$50).
- Direct sale on talktype.app/mac is **A$59** (~US$39) — the same product at the same value, with no store fee in the middle. Never mention that inside the app.
- No subscription and no TalkType-hosted transcription charges. Optional provider usage remains on the user’s own provider account.

## App Store icon

`screenshots/appicon-1024.png` — 1024×1024, no transparency, exported from `Assets/AppIcon.icns`.

## Screenshot story

Use real captures from the Mac App Store build, with short captions and one consistent peach, pink, and cream treatment.

1. **Say it messy. Get it clean.** Show the ghost and a short, polished sample transcript.
2. **A little ghost, right in your menu bar.** Show the real start-dictation interaction.
3. **Give it your words.** Show custom vocabulary with a friendly example name.
4. **Your recent words, close by.** Show transcript history and its delete controls.
5. **Choose your speech setup.** Show Apple Speech and the optional cloud choices with accurate labels.

Keep every screenshot’s controls and behavior true to the shipped App Store build. Do not promise a global shortcut or automatic paste unless that exact build supports it.

## Still needed before submission

- Finalize the in-app privacy link (the MAS build currently opens the *web app* policy — point it at a Mac-specific one) and the App Store privacy answers: **Data Not Collected**.
- Confirm the App Store build’s dictation, clipboard, shortcut, and cloud behavior, then revise any copy that depends on it.
- Localize the approved listing and screenshot captions into Spanish.
- Replace the current App Store screenshot with a clean, intentional sample transcript.
