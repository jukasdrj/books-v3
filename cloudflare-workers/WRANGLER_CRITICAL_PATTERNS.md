# 🚨 CRITICAL: Wrangler.toml Structure Patterns

**NOTE:** BooksTrack now uses a monolith architecture (single api-worker). Service binding patterns below are for historical reference and future multi-worker architectures.

**CURRENT ARCHITECTURE:** See `MONOLITH_ARCHITECTURE.md` for the consolidated api-worker configuration.

**MEMORIZE THESE PATTERNS** - Critical knowledge for Cloudflare Workers configuration

---

## 🔥 **TOML STRUCTURE FUNDAMENTALS**

### **✅ CORRECT: Table Array Syntax for Secrets**
```toml
# CORRECT - Use double brackets for table arrays
[[secrets_store_secrets]]
binding = "GOOGLE_BOOKS_API_KEY"
store_id = "b0562ac16fde468c8af12717a6c88400"
secret_name = "Google_books_hardoooe"

[[secrets_store_secrets]]
binding = "ISBNDB_API_KEY"
store_id = "b0562ac16fde468c8af12717a6c88400"
secret_name = "ISBNDB_API_KEY"
```

### **❌ INCORRECT: Array Syntax (Will Cause Deployment Failures)**
```toml
# WRONG - This syntax will fail with "Unexpected fields" error
secrets_store_secrets = [
  {
    binding = "GOOGLE_BOOKS_API_KEY",
    store_id = "b0562ac16fde468c8af12717a6c88400",
    secret_name = "Google_books_hardoooe"
  }
]
```

---

## 🔗 **SERVICE BINDING PATTERNS**

### **✅ CORRECT: Unidirectional Service Binding Architecture**
```toml
# personal-library-cache-warmer/wrangler.toml
[[services]]
binding = "BOOKS_API_PROXY"
service = "books-api-proxy"

[[services]]
binding = "ISBNDB_WORKER"
service = "isbndb-biography-worker-production"

# books-api-proxy/wrangler.toml
[[services]]
binding = "ISBNDB_WORKER"
service = "isbndb-biography-worker-production"

# isbndb-biography-worker/wrangler.toml
# No service bindings - leaf node
```

### **Service Binding Communication Flow**
```
personal-library-cache-warmer
    ↓ calls via BOOKS_API_PROXY binding
books-api-proxy
    ↓ calls via ISBNDB_WORKER binding
isbndb-biography-worker-production
```

---

## 🌐 **SERVICE BINDING CALL PATTERNS**

### **✅ CORRECT: Relative Path Service Calls**
```javascript
// CORRECT - Use relative paths with service bindings
const response = await env.ISBNDB_WORKER.fetch(
  new Request(`/author/${encodeURIComponent(author)}`)
);

const cacheResponse = await env.BOOKS_API_PROXY.fetch(
  new Request(`/search/auto?q=${encodeURIComponent(query)}`)
);
```

### **❌ INCORRECT: Full URL Service Calls (HTTP Overhead)**
```javascript
// WRONG - This defeats the purpose of service bindings
const response = await env.ISBNDB_WORKER.fetch(
  new Request(`https://isbndb-biography-worker-production.jukasdrj.workers.dev/author/${author}`)
);
```

---

## 📋 **COMPLETE WRANGLER.TOML TEMPLATE**

### **Full Working Configuration Pattern**
```toml
# Worker identification
name = "worker-name"
main = "src/index.js"
compatibility_date = "2024-09-17"
compatibility_flags = ["nodejs_compat"]

# Performance limits
limits = { cpu_ms = 30000 }

# Observability
[observability]
enabled = true

# Secrets management - CRITICAL SYNTAX
[[secrets_store_secrets]]
binding = "API_KEY_BINDING_NAME"
store_id = "your-store-id"
secret_name = "actual-secret-name-in-store"

# Service bindings - only bind to workers you call
[[services]]
binding = "SERVICE_BINDING_NAME"
service = "target-worker-name"

# KV storage
[[kv_namespaces]]
binding = "KV_BINDING_NAME"
id = "kv-namespace-id"

# R2 storage
[[r2_buckets]]
binding = "R2_BINDING_NAME"
bucket_name = "bucket-name"

# Environment variables
[vars]
VARIABLE_NAME = "value"

# Cron triggers (optional)
[triggers]
crons = ["*/15 * * * *"]
```

---

## 🚨 **CRITICAL ERROR PATTERNS TO AVOID**

### **1. TOML Structure Errors**
```bash
# Error: "Unexpected fields found in r2_buckets[0] field: 'secrets_store_secrets'"
# Cause: Incorrect array syntax instead of table arrays
# Fix: Use [[secrets_store_secrets]] not secrets_store_secrets = [...]
```

### **2. Service Binding Call Errors**
```bash
# Error: High latency, network timeouts
# Cause: Using full URLs instead of relative paths
# Fix: Use "/endpoint" not "https://worker.domain.workers.dev/endpoint"
```

### **3. Secret Access Errors**
```bash
# Error: "Cannot read properties of undefined (reading 'get')"
# Cause: Malformed secret binding configuration
# Fix: Ensure proper [[secrets_store_secrets]] table syntax
```

---

## 🔧 **DEBUGGING COMMANDS**

### **Deployment Verification**
```bash
# Deploy and check for warnings
wrangler deploy

# Tail logs for real-time debugging
wrangler tail --format pretty

# List KV keys (production data)
wrangler kv key list --binding CACHE --remote

# Test specific endpoints
curl "https://worker-name.domain.workers.dev/test-endpoint"
```

### **Service Binding Testing**
```javascript
// Add to worker code for debugging service bindings
console.log('Service binding test:', {
  bindingExists: !!env.SERVICE_BINDING_NAME,
  bindingType: typeof env.SERVICE_BINDING_NAME
});

// Test relative path calls
const testResponse = await env.SERVICE_BINDING_NAME.fetch(
  new Request('/health')
);
console.log('Service binding response:', testResponse.status);
```

---

## 📊 **PERFORMANCE IMPACT**

### **Before Service Binding Optimization**
- **Inter-worker calls**: 200-500ms (HTTP overhead)
- **Network latency**: 50-100ms per call
- **DNS resolution**: 20-50ms per call

### **After Service Binding Optimization**
- **Inter-worker calls**: 10-50ms (direct binding)
- **Network latency**: 0ms (internal routing)
- **DNS resolution**: 0ms (no external calls)

**Performance Improvement**: **10-20x faster** inter-worker communication

---

## 🎯 **SUCCESS VERIFICATION CHECKLIST**

### **Deployment Success**
- [ ] `wrangler deploy` completes without warnings
- [ ] No "Unexpected fields" errors in TOML
- [ ] All secret bindings show as available in logs

### **Service Binding Success**
- [ ] Inter-worker calls use relative paths (`/endpoint`)
- [ ] Response times under 50ms for service binding calls
- [ ] No HTTP 404 errors in service binding calls

### **API Integration Success**
- [ ] Secret access working (`env.SECRET_NAME` accessible)
- [ ] External API calls returning valid responses
- [ ] Service binding chain working end-to-end

---

## 🚀 **DEPLOYMENT WORKFLOW**

### **Safe Deployment Pattern**
1. **Fix TOML Structure**: Ensure proper table array syntax
2. **Test One Worker**: Deploy and verify single worker functionality
3. **Verify Bindings**: Test all service bindings and secret access
4. **Apply Pattern**: Copy working configuration to other workers
5. **End-to-End Test**: Verify complete service binding chain

### **Emergency Rollback**
```bash
# If deployment fails, immediately rollback
wrangler rollback

# Check previous deployment versions
wrangler deployments list

# Rollback to specific version
wrangler rollback --version-id VERSION_ID
```

---

**🔥 MEMORIZE: The most critical pattern is the `[[secrets_store_secrets]]` table array syntax and using relative paths for service binding calls. These two patterns prevent 90% of CloudFlare Workers configuration issues.**