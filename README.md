# Voice Notes

Voice Notes is a menu-bar app for macOS 15. Hold a key, speak, and the transcript is pasted into whatever app you were typing in. Audio is transcribed on this Mac and never leaves it. In the default Cleaned mode, only the finished text is sent to OpenAI to fix grammar, drop filler, and format lists.

The app has no Dock icon. Look for the waveform in the menu bar.

## First launch

Open the app, then allow each permission it asks for:

- **Microphone** so it can hear you
- **Speech Recognition** so Apple Speech can transcribe on this Mac
- **Accessibility** so it can paste with Command-V
- **Input Monitoring** so the global shortcuts work

Accessibility and Input Monitoring take effect only after you quit Voice Notes and open it again. If a shortcut does nothing, open **Settings** from the menu bar and use the **Open** button next to any permission that is still off.

## Dictate

Click in the app where you want the text, such as Notes, Mail, or a browser.

- **Hold the right Option key** while you speak, then release. A short tap does not paste. Hold it for about half a second or longer, speak, and release to finish.
- **Double-tap the right Option key** to record hands-free. Tap it once more to finish and paste.
- **Esc** cancels the current recording. Nothing is transcribed, saved, or pasted.

Right Option and Esc are the only keys Voice Notes listens for. Left Option, Fn, arrow keys, and everything else pass through so you can keep typing. While recording, a small pill at the bottom of the screen shows the live transcript. Esc cancels it.

A start sound and a stop sound play around each recording. Turn them off under Settings → Output.

## Cleaned and raw text

**Cleaned** is the default. Apple Speech transcribes on your Mac, then the transcript text goes to OpenAI (`gpt-5-mini`, unless you change the model in Settings). The cleaned text is what gets pasted. The note keeps both the original transcript and the cleaned version.

Add an API key in Settings → Transcription and choose **Save Key**. The key is stored in the Keychain.

If OpenAI cannot be reached, Voice Notes pastes the raw transcript and shows an alert. If the key is missing or cleanup fails for another reason, the raw transcript is saved and is not pasted.

**Raw** pastes and stores the on-device transcript unchanged. No text is sent to OpenAI.

**Paste into the focused app** is on by default. Turn it off to save notes without pasting. Every successful transcription is still saved.

## Notes

Choose **Notes** in the menu bar to search, copy, paste again, or delete saved notes. **Paste Last Note** pastes the newest one into the focused app.

Notes are stored on this Mac at `~/Library/Application Support/VoiceNotes/notes.json`.

## Build and run

You need an Apple silicon Mac on macOS 15 or later.

```bash
./Scripts/build.sh
open build/VoiceNotes.app
```

That script runs the shortcut and cleanup checks, then builds `build/VoiceNotes.app`. If Xcode is installed, it uses `xcodebuild test` instead. You can also open `VoiceNotes.xcodeproj` and run the VoiceNotes scheme.
