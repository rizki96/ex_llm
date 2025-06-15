# ExLLM Streaming Enhancements

## Overview

This document describes the enhanced streaming infrastructure being added to ExLLM, based on proven patterns from MCP Chat. These enhancements provide better flow control, memory efficiency, and user experience when streaming LLM responses.

## Key Components

### 1. StreamBuffer - Circular Buffer Implementation

A memory-efficient circular buffer that prevents unbounded memory growth during streaming.

**Features:**
- Fixed-size buffer with configurable capacity
- O(1) push/pop operations for optimal performance
- Overflow detection and handling strategies
- Fill percentage monitoring for backpressure decisions
- Batch operations (`pop_many`) for efficient chunk processing

**Benefits:**
- Prevents memory issues with fast producers
- Efficient chunk management
- Clear overflow handling strategies

### 2. FlowController - Advanced Flow Control

Manages the flow of data between fast producers (LLM APIs) and potentially slow consumers (terminals, network connections).

**Features:**
- Producer/consumer pattern with separate async tasks
- Configurable buffer thresholds for backpressure
- Automatic rate limiting when consumers fall behind
- Comprehensive metrics tracking
- Graceful degradation under load

**Benefits:**
- No dropped chunks with slow consumers
- Smooth streaming even with variable speeds
- Better system resource utilization

### 3. ChunkBatcher - Intelligent Batching

Optimizes chunk delivery by intelligently batching small chunks together.

**Features:**
- Configurable batch size and timeout
- Min/max batch size constraints
- Adaptive batching based on chunk size
- Reduced I/O operations

**Benefits:**
- Fewer system calls (better performance)
- Smoother terminal output
- Reduced CPU usage

## Configuration Options

### Consumer Types

1. **`:direct`** (default) - Current behavior, chunks passed directly to callback
2. **`:buffered`** - Basic buffering with overflow protection
3. **`:managed`** - Full flow control with backpressure and batching

### Configuration Structure

```elixir
streaming_options: [
  # Consumer type selection
  consumer_type: :managed,
  
  # Buffer configuration
  buffer_config: %{
    capacity: 100,              # Maximum chunks to buffer
    overflow_strategy: :drop,   # :drop | :block | :overwrite
  },
  
  # Batch configuration
  batch_config: %{
    size: 5,                    # Target batch size
    timeout_ms: 25,             # Max time to wait for batch
    min_size: 3,                # Minimum chunks before batching
    max_size: 10                # Maximum chunks per batch
  },
  
  # Flow control settings
  flow_control: %{
    enabled: true,
    slow_threshold_ms: 50,      # When to consider consumer slow
    backpressure_threshold: 0.8 # Buffer fill ratio to apply backpressure
  },
  
  # Metrics collection
  metrics: %{
    enabled: true,
    interval_ms: 1000           # How often to report metrics
  }
]
```

## Usage Examples

### Basic Enhanced Streaming

```elixir
# Use managed streaming for better performance
ExLLM.stream_chat(:anthropic, messages, fn chunk ->
  IO.write(chunk.content)
end, streaming_options: [consumer_type: :managed])
```

### Custom Configuration

```elixir
# Configure for a slow terminal
ExLLM.stream_chat(:groq, messages, fn chunk ->
  slow_terminal_write(chunk.content)
end, streaming_options: [
  consumer_type: :managed,
  buffer_config: %{capacity: 200},
  batch_config: %{size: 10, timeout_ms: 50}
])
```

### With Metrics Tracking

```elixir
# Track streaming performance
ExLLM.stream_chat(:openai, messages, fn chunk ->
  process_chunk(chunk)
end, streaming_options: [
  consumer_type: :managed,
  metrics: %{enabled: true},
  on_metrics: fn metrics ->
    Logger.info("Streaming metrics: #{inspect(metrics)}")
  end
])
```

## Implementation Phases

### Phase 1: Core Infrastructure (Current)
- Implement StreamBuffer module
- Implement FlowController module  
- Implement ChunkBatcher module

### Phase 2: Integration
- Enhance StreamingCoordinator with new options
- Add consumer type selection logic
- Wire up configuration parsing

### Phase 3: Testing & Optimization
- Comprehensive test suite
- Performance benchmarks
- Documentation updates

## Performance Considerations

1. **Memory Usage**: Circular buffers have fixed memory overhead
2. **CPU Usage**: Batching reduces system calls but adds minimal processing
3. **Latency**: Small timeout values (25ms) ensure low perceived latency
4. **Throughput**: Batching improves throughput with fast producers

## Backwards Compatibility

All enhancements are opt-in. Existing code continues to work unchanged:

```elixir
# This still works exactly as before
ExLLM.stream_chat(:anthropic, messages, fn chunk ->
  IO.write(chunk.content)
end)
```

## Migration Guide

For users wanting to adopt the new features:

1. **Slow Terminal Issues**: Use `consumer_type: :managed`
2. **Memory Concerns**: Configure buffer capacity limits
3. **Performance Optimization**: Enable batching with appropriate sizes
4. **Debugging**: Enable metrics to understand streaming behavior