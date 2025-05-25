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
- New public API functions in main ExLLM module:
  - `prepare_messages/2` - Prepare messages for context window
  - `validate_context/2` - Validate messages fit within context
  - `context_window_size/2` - Get model context window size
  - `context_stats/1` - Get context usage statistics
- Automatic context management in `chat/3` and `stream_chat/3`
- Comprehensive test coverage for context management

### Changed
- Updated `chat/3` and `stream_chat/3` to automatically apply context truncation
- Enhanced documentation with context management examples

## [0.1.0] - 2025-01-24

### Added
- Initial release with unified LLM interface
- Support for Anthropic Claude models
- Streaming support via Server-Sent Events
- Integrated cost tracking and calculation
- Token estimation functionality
- Configurable provider system
- Comprehensive error handling