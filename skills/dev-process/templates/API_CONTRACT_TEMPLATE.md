# {{PROJECT_NAME}} — API 契约文档

> 创建时间: {{CREATED_DATE}}
> 项目类型: Web

## Base URL

```
Development: http://localhost:3000/api
Production:  https://api.example.com
```

## Authentication

<!-- 认证方式 -->

| 方式 | Header | 格式 |
|------|--------|------|
| -    | -      | -    |

## Response Format

所有 API 统一响应格式：

```json
{
  "success": true,
  "data": {},
  "error": null
}
```

错误响应：

```json
{
  "success": false,
  "data": null,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message"
  }
}
```

## Endpoints

### `GET /api/resource`

**描述**:
**认证**: 需要/不需要
**参数**:

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| -    | -    | -    | -    |

**成功响应** (200):
```json
{}
```

**错误响应**:
| 状态码 | Error Code | 说明 |
|--------|-----------|------|
| 400    | -         | -    |

---

## Error Codes

| Code | HTTP Status | 说明 | 处理建议 |
|------|-------------|------|---------|
| VALIDATION_ERROR | 400 | 参数校验失败 | 检查请求参数 |
| UNAUTHORIZED | 401 | 未认证 | 重新登录 |
| FORBIDDEN | 403 | 无权限 | 联系管理员 |
| NOT_FOUND | 404 | 资源不存在 | 检查 ID |
| INTERNAL_ERROR | 500 | 服务器错误 | 重试或联系后端 |

## TypeScript Interfaces

```typescript
// 在此定义前后端共享的类型

interface ApiResponse<T> {
  success: boolean;
  data: T | null;
  error: ApiError | null;
}

interface ApiError {
  code: string;
  message: string;
}
```

## Rate Limiting

<!-- 限流策略（如有） -->

## Versioning

<!-- API 版本策略 -->
