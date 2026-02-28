# Web 项目专属规范

> 适用于前后端分离的 Web 项目。补充 PROCESS_GUIDE.md 的通用流程。

## 前后端分离约定

### 目录结构

```
project/
├── docs/
│   ├── API_CONTRACT.md    ← Web 项目专属
│   └── ...
├── src/
│   ├── client/            ← 前端代码
│   │   ├── components/
│   │   ├── pages/
│   │   ├── hooks/
│   │   ├── utils/
│   │   └── types/         ← 共享类型定义
│   └── server/            ← 后端代码
│       ├── routes/
│       ├── controllers/
│       ├── models/
│       ├── middleware/
│       └── utils/
├── tests/
│   ├── unit/
│   ├── integration/
│   └── e2e/
└── CLAUDE.md
```

### 前后端协作原则

1. **API 契约先行**：先定义 API_CONTRACT.md，前后端并行开发
2. **类型共享**：TypeScript 接口定义在共享位置，前后端引用同一份
3. **Mock 先行**：前端基于 API 契约写 mock，不等后端完成

## API 设计规范

### RESTful 约定

| 操作 | HTTP Method | URL Pattern | 状态码 |
|------|-------------|-------------|--------|
| 列表 | GET | /api/resources | 200 |
| 详情 | GET | /api/resources/:id | 200/404 |
| 创建 | POST | /api/resources | 201/400 |
| 更新 | PUT/PATCH | /api/resources/:id | 200/404 |
| 删除 | DELETE | /api/resources/:id | 204/404 |

### 统一响应格式

```typescript
interface ApiResponse<T> {
  success: boolean;
  data: T | null;
  error: {
    code: string;
    message: string;
  } | null;
}
```

### 分页约定

```typescript
interface PaginatedResponse<T> {
  success: true;
  data: {
    items: T[];
    total: number;
    page: number;
    pageSize: number;
  };
  error: null;
}
```

Query: `?page=1&pageSize=20&sort=createdAt&order=desc`

### 错误码体系

| 前缀 | 含义 | 示例 |
|------|------|------|
| VALIDATION_ | 参数校验 | VALIDATION_REQUIRED, VALIDATION_FORMAT |
| AUTH_ | 认证授权 | AUTH_EXPIRED, AUTH_FORBIDDEN |
| RESOURCE_ | 资源操作 | RESOURCE_NOT_FOUND, RESOURCE_CONFLICT |
| SYSTEM_ | 系统错误 | SYSTEM_INTERNAL, SYSTEM_UNAVAILABLE |

## 安全清单

### 必须检查项

- [ ] **输入验证**: 所有用户输入在服务端验证（不信任前端验证）
- [ ] **SQL 注入**: 使用参数化查询或 ORM，永远不拼接 SQL
- [ ] **XSS**: 输出编码，CSP header，不用 `dangerouslySetInnerHTML`
- [ ] **CSRF**: 使用 CSRF token 或 SameSite cookie
- [ ] **认证**: 密码哈希（bcrypt/argon2），JWT 有过期时间
- [ ] **授权**: 每个 API 检查权限，不仅仅靠前端隐藏按钮
- [ ] **CORS**: 仅允许可信域名
- [ ] **Rate Limiting**: 登录/注册/敏感操作有限流
- [ ] **Secrets**: 环境变量管理，不硬编码，.env 在 .gitignore 中
- [ ] **依赖安全**: 定期 `npm audit`，及时更新有漏洞的包

### 敏感数据处理

- 密码：永远不存明文，使用 bcrypt/argon2
- Token：存 httpOnly cookie，不存 localStorage
- 日志：脱敏处理，不打印密码/token
- 传输：强制 HTTPS

## 前端规范

### 状态管理

- 简单应用：React Context + useReducer
- 复杂应用：Zustand / Redux Toolkit
- 服务端状态：TanStack Query (React Query)

### 性能基线

| 指标 | 目标值 |
|------|--------|
| LCP | < 2.5s |
| FID | < 100ms |
| CLS | < 0.1 |
| Bundle Size (gzip) | < 200KB (initial) |

## 后端规范

### 中间件顺序

```
1. CORS
2. Body parser
3. Rate limiter
4. Auth middleware
5. Route handlers
6. Error handler (catch-all)
```

### 数据库约定

- Migration 文件有版本号，不手动改 schema
- 索引：查询频繁的字段必须加索引
- 关联：外键约束在数据库层面保证
- 软删除：业务数据用 `deletedAt` 而不是物理删除

### 日志规范

```typescript
// 结构化日志
logger.info('user.login', { userId, ip, userAgent });
logger.error('order.create.failed', { orderId, error: err.message });
```

- 用结构化 JSON，不用 `console.log`
- 包含 requestId 用于链路追踪
- 敏感信息脱敏
