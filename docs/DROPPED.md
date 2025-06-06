# Dropped Features

This document contains features that were considered but ultimately dropped from the ExLLM roadmap. These features either:
- Don't align with the library's core mission of being a unified LLM client
- Are better served by external tools or separate projects
- Add excessive complexity for minimal value
- Should be handled at the application layer rather than library level

## Enterprise Features (Dropped - Better as Separate Product)

These features would be better implemented as a separate enterprise product that uses ExLLM as a dependency:

### Proxy Server / API Gateway Mode
- Would transform the library into an infrastructure component
- Better served by dedicated solutions like Kong, Envoy, or cloud API gateways
- Adds significant complexity and maintenance burden

### Web UI for Management
- Should be a separate project/application
- Would require frontend framework dependencies
- Not aligned with being a client library

### Team and Budget Management
- Application-level concern, not library-level
- Requires persistent storage, user management, etc.
- Better suited for a management platform built on top of ExLLM

### SSO/SAML Authentication
- Authentication should be handled at the application layer
- Would require significant security considerations
- Not part of core LLM interaction functionality

### Service Accounts
- Application-level user management concern
- Should be implemented by applications using the library

### Audit Logs
- Should be handled via the callback/telemetry system
- Applications can implement their own audit logging
- Library should emit events, not manage logs

### Rate Limiting per API Key
- While useful, this is better handled at the application or API gateway layer
- Library can emit metrics for rate limit tracking

## Overly Complex Features (Dropped)

### Semantic Caching with Similarity Search
- Requires vector database dependencies
- Adds significant complexity for marginal benefit over simple caching
- Users who need this can implement it using the existing cache behavior

### Multi-conversation Context Sharing
- Complex coordination requirements
- Unclear use cases and benefits
- Better handled at application level if needed

### Token-level Streaming (not just chunk-level)
- Most providers only support chunk-level streaming
- Would require complex client-side processing
- Minimal practical benefit for the added complexity

### Fake Streaming for Non-streaming Providers
- Adds complexity without real value
- Clients can handle non-streaming responses appropriately
- Could create confusion about actual provider capabilities

## Better Served by External Tools

### Load Testing Utilities
- Better served by existing tools like k6, JMeter, or Elixir's Chaperon
- Users can load test their applications that use ExLLM
- Not a core responsibility of an LLM client library

### Multiple Monitoring Integrations (Langfuse, Langsmith, DataDog)
- Better to provide a single extensible callback system
- Let users integrate with their preferred monitoring tools
- Avoids dependencies on specific monitoring services

## Migration Notes

If you're looking for these features:

1. **Enterprise Features**: Consider building a management layer on top of ExLLM
2. **Monitoring**: Use the callback system to integrate with your monitoring solution
3. **Load Testing**: Use standard load testing tools against your application
4. **Authentication**: Implement at your application layer
5. **Caching**: Use the simple cache for basic needs, implement semantic search separately if needed

## Future Reconsideration

Some of these features might be reconsidered if:
- There's overwhelming user demand
- The implementation complexity decreases significantly
- They can be implemented as optional add-on packages
- The core library architecture evolves to better support them

However, the focus remains on ExLLM being the best unified LLM client library for Elixir, not an all-in-one platform.