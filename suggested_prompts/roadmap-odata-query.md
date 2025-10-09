# OData Query Cheat Sheet for M365 Feature Updates

## ✅ Base Entity
`M365` – Represents Microsoft 365 feature updates.

---

## Core Query Options

### 1. Select Specific Fields
```http
?$select=id,title,status,created,modified
```

### 2. Order By
```http
?$orderby=modified desc
```

### 3. Top N Results
```http
?$top=10
```

### 4. Count
```http
?$count=true
```
*(Returns total count of matching entities in response)*

### 5. Search
```http
?$search="Excel"
```
*(Full-text search across searchable fields)*

---

## Filter Examples by Field

### Primitive Fields
- **By ID**
```http
?$filter=id eq 65632
```

- **By Title (substring)**
```http
?$filter=contains(title,'Excel')
```

- **By Status**
```http
?$filter=status eq 'In development'
```

- **By Created Date**
```http
?$filter=created gt 2023-01-01T00:00:00Z
```

- **By Modified Date**
```http
?$filter=modified lt 2025-05-01T00:00:00Z
```

- **By General Availability Date**
```http
?$filter=generalAvailabilityDate eq '2025-05'
```

---

### Collection Fields
- **Products**
```http
?$filter=products/any(p: p eq 'Excel')
```

- **Cloud Instances**
```http
?$filter=cloudInstances/any(c: c eq 'GCC High')
```

- **Platforms**
```http
?$filter=platforms/any(p: p eq 'Web')
```

- **Release Rings**
```http
?$filter=releaseRings/any(r: r eq 'General Availability')
```

---

### Complex Type (`availabilities`)
- **Expand and Filter**
```http
?$expand=availabilities&$filter=availabilities/any(a: a/year eq 2025 and a/month eq 'May')
```

- **Select Nested Fields**
```http
?$expand=availabilities($select=ring,year,month)
```

---

## Composite Queries
- **Excel updates in GCC High with GA in May 2025**
```http
?$filter=products/any(p: p eq 'Excel') and cloudInstances/any(c: c eq 'GCC High') and generalAvailabilityDate eq '2025-05'
```

- **Updates in development for Web platform**
```http
?$filter=status eq 'In development' and platforms/any(p: p eq 'Web')
```

---

## Advanced Examples
- **Search + Order + Count**
```http
?$search="Excel"&$orderby=modified desc&$count=true
```

- **Expand + Select + Filter**
```http
?$expand=availabilities($select=ring,year,month)&$select=id,title,status&$filter=status eq 'In development'
```

---

### ✅ Quick Tips
- Use `any()` for collections.
- Use `contains()` for substring matching.
- `$expand` is essential for nested/complex types.
- `$search` works only if the service supports full-text search.
- `$count=true` adds total count metadata.
