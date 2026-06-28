/// Per-chat thinking/reasoning mode for models that expose the `thinking`
/// capability. Mirrors the OpenWebUI web client's 3-state pill.
///
/// Wire format (sent to the chat-completions request):
///  - [on]   -> params.chat_template_kwargs.enable_thinking = true
///  - [off]  -> params.chat_template_kwargs.enable_thinking = false
///  - [auto] -> no enable_thinking; features.thinking_mode = 'auto', letting a
///              server-side inlet filter decide per message (degrades to the
///              model's default when no filter is installed).
enum ThinkingMode { on, auto, off }

/// Parses the persisted/serialized name back to a [ThinkingMode], defaulting to
/// [ThinkingMode.auto] for anything unrecognized or null.
ThinkingMode thinkingModeFromName(String? name) {
  switch (name) {
    case 'on':
      return ThinkingMode.on;
    case 'off':
      return ThinkingMode.off;
    case 'auto':
      return ThinkingMode.auto;
    default:
      return ThinkingMode.auto;
  }
}
