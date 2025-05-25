# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Context management functionality to automatically handle LLM context windows
- `ExLLM.Context` module with the following features:
  - Automatic message truncation to fit within model context windows
  - Multiple truncation strategies (sliding_window, smart)
  - Context window validation
  - Token estimation and statistics
  - Model-specific context window sizes
- Session management functionality for conversation state tracking
- `ExLLM.Session` module with the following features:
  - Conversation state management
  - Message history tracking
  - Token usage tracking
  - Session persistence (save/load)
  - Export to markdown/JSON formats
- New public API functions in main ExLLM module:
  - Context management: `prepare_messages/2`, `validate_context/2`, `context_window_size/2`, `context_stats/1`
  - Session management: `new_session/2`, `chat_with_session/2`, `save_session/2`, `load_session/1`, etc.
- Automatic context management in `chat/3` and `stream_chat/3`
- Comprehensive test coverage for context and session management

### Changed
- Updated `chat/3` and `stream_chat/3` to automatically apply context truncation
- Enhanced documentation with context management and session examples
- ExLLM is now a comprehensive all-in-one solution including cost tracking, context management, and session handling

## [0.1.0] - 2025-01-24

### Added
- Initial release with unified LLM interface
- Support for Anthropic Claude models
- Streaming support via Server-Sent Events
- Integrated cost tracking and calculation
- Token estimation functionality
- Configurable provider system
- Comprehensive error handling