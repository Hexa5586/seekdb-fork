# seekdb 本地试用指南

本指南记录在 **WSL2 Ubuntu 22.04** 上从源码编译、启动 seekdb，并完成基础 SQL 与向量检索的步骤。
所有命令都在仓库根目录 `seekdb-fork/` 下执行，示例输出来自本机实测。

---

## 1. 本机环境评估

| 项目 | 实测值 | 结论 |
| --- | --- | --- |
| 系统 | WSL2 Ubuntu 22.04.5 LTS, x86_64 | ✅ 在依赖初始化支持列表内 |
| CPU | 20 逻辑核 | ✅ |
| 内存 | 7.5 GiB（Windows 主机 15.4 GiB，WSL 上限约一半） | ⚠️ 偏紧，需限制并发 |
| 磁盘 | 936 GB 可用 | ✅ |
| 编译器 | gcc / g++ 11.4.0 | ✅ |
| Rust | rustc 1.100.0，与 `rust-toolchain.toml` 一致 | ✅ |
| 网络 | github.com、rsproxy.cn 可访问 | ✅ |
| 前置工具 | git/wget/curl/rpm2cpio/cpio/make/m4/file/python3 均在 | ✅ |
| 运行时库 | 缺 `libaio.so.1`（系统未安装 `libaio1`） | ⚠️ 见第 6 节 |

**结论：本机可以编译并运行 seekdb。**

实测数据：

- `./build.py init`：成功，依赖落在 `deps/3rd/`，约 **4.5 GB**，自带 `obclient`、`mysqltest`。
- `./build.py build -j6 seekdb`：成功，**2920 个动作，约 11 分钟**（Rust/Bazel 缓存已就绪时），产物 `build/bin/src/observer/seekdb`，**1.1 GB**。
- 低内存是唯一风险点：`-j6` 时内存占用约 3.6 GiB，峰值余量约 3.7 GiB，未触发 OOM。若想更快可尝试 `-j8`，但需先给 WSL 提高内存上限（在 `C:\Users\<you>\.wslconfig` 中设置 `memory=`，然后 `wsl --shutdown`）。

---

## 2. 编译

```bash
cd seekdb-fork

# 首次构建、或修改了依赖清单 / rust-toolchain.toml 后执行
./build.py init

# 增量构建；低内存机器建议限制并发
./build.py build -j6 seekdb
```

产物路径：`build/bin/src/observer/seekdb`。

> 构建目录默认是 `build/`。可用 `-o build2` 指定独立构建目录；`./build.py info output_base` 查看实际工作目录。

---

## 3. 启动与连接

根目录提供了三个封装脚本，默认实例目录是 `build/dev-instance`，端口 `2881`。

### 3.1 启动

```bash
./start.sh
```

脚本会启动 seekdb 并等待 `SELECT 1` 成功，就绪后返回。可通过环境变量覆盖默认值：

```bash
SEEKDB_BASE_DIR=$PWD/build/my-instance SEEKDB_PORT=2882 ./start.sh
```

| 变量 | 默认值 |
| --- | --- |
| `SEEKDB_BASE_DIR` | `$PWD/build/dev-instance` |
| `SEEKDB_PORT` | `2881` |

空数据目录会自动初始化。

### 3.2 连接

```bash
./sql.sh                 # 交互式，默认 root、无密码
```

非交互执行：

```bash
./sql.sh -e "select version();"
# 5.7.25-OceanBase seekdb-v1.4.1.0
```

`./sql.sh` 会把参数原样传给 `deps/3rd/u01/obclient/bin/obclient`，因此 `-e`、`-N -s`、`-D` 等都可直接使用。
连接其他端口：`SEEKDB_PORT=2882 ./sql.sh`。

### 3.3 停止

```bash
./stop.sh               # 停进程，保留数据
```

删除实例及其数据：

```bash
python3 tools/deploy/sdb.py destroy --base-dir "${SEEKDB_BASE_DIR:-$PWD/build/dev-instance}"
```

重启时再次执行 `./start.sh` 即可。

---

## 4. 数据增删改查

```sql
CREATE DATABASE IF NOT EXISTS demo;
USE demo;

CREATE TABLE users (
  id         INT PRIMARY KEY,
  name       VARCHAR(32) NOT NULL,
  age        INT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 增
INSERT INTO users (id, name, age) VALUES
  (1,'alice',30), (2,'bob',25), (3,'carol',35);

-- 查
SELECT * FROM users ORDER BY id;
```

实测输出：

```
id	name	age	created_at
1	alice	30	2026-11-21 09:08:08
2	bob	25	2026-11-21 09:08:08
3	carol	35	2026-11-21 09:08:08
```

```sql
-- 改
UPDATE users SET age = 26 WHERE id = 2;
SELECT * FROM users WHERE id = 2;
-- 删
DELETE FROM users WHERE id = 3;
SELECT COUNT(*) AS cnt FROM users;
```

实测输出：

```
id	name	age	created_at
2	bob	26	2026-11-21 09:08:08

cnt
2
```

元数据操作与 MySQL 一致：

```sql
SHOW TABLES;   -- Tables_in_demo: users
DESC users;
```

```
Field	Type	Null	Key	Default	Extra
id	int(11)	NO	PRI	NULL
name	varchar(32)	NO		NULL
age	int(11)	YES		NULL
created_at	datetime	YES		CURRENT_TIMESTAMP
```

事务示例：

```sql
START TRANSACTION;
UPDATE users SET age = age + 1 WHERE id = 1;
ROLLBACK;
SELECT age FROM users WHERE id = 1;   -- 仍是 30
```

---

## 5. 简单向量检索

### 5.1 建表与向量索引

向量列类型是 `VECTOR(N)`，值写成 `'[v1,v2,...]'` 字符串（长度必须等于 N）。
向量索引在建表时内联定义，或在之后 `CREATE VECTOR INDEX` 追加。

```sql
USE demo;

CREATE TABLE doc_vectors (
  id        INT PRIMARY KEY,
  title     VARCHAR(64),
  category  VARCHAR(16),
  embedding VECTOR(4),
  VECTOR INDEX idx_vec (embedding) WITH (distance=cosine, type=hnsw, lib=vsag)
);

INSERT INTO doc_vectors VALUES
  (1,'apple fruit','food',    '[1.0,0.0,0.0,0.0]'),
  (2,'banana fruit','food',   '[0.9,0.1,0.0,0.0]'),
  (3,'orange juice','drink',  '[0.8,0.2,0.1,0.0]'),
  (4,'red bike','vehicle',    '[0.0,1.0,0.0,0.0]'),
  (5,'blue car','vehicle',    '[0.0,0.9,0.2,0.0]');
```

索引确认：

```sql
SHOW INDEX FROM doc_vectors;
```

```
Key_name   Column_name  Index_type
PRIMARY    id           BTREE
idx_vec    embedding    VECTOR
```

索引参数说明：

| 参数 | 取值 | 说明 |
| --- | --- | --- |
| `distance` | `l2` / `cosine` / `inner_product` | 距离度量 |
| `type` | `hnsw` / `ivf_flat` / `ivf_sq8` / `ivf_pq` | 索引算法 |
| `lib` | `vsag` | 向量索引库 |
| `m` / `ef_construction` / `ef_search` | 整数 | HNSW 参数，可省略走默认值 |

### 5.2 近似检索

用距离函数 + `ORDER BY ... APPROXIMATE` 触发向量索引：

```sql
SELECT id, title, category, cosine_distance(embedding, '[1.0,0.0,0.0,0.0]') AS dist
FROM doc_vectors
ORDER BY dist APPROXIMATE
LIMIT 3;
```

实测输出：

```
id	title	category	dist
1	apple fruit	food	0
2	banana fruit	food	0.006116257407132508
3	orange juice	drink	0.03691319504662416
```

### 5.3 标量过滤 + 向量检索

```sql
SELECT id, title, category, cosine_distance(embedding, '[0.0,1.0,0.0,0.0]') AS dist
FROM doc_vectors
WHERE category = 'vehicle'
ORDER BY dist APPROXIMATE
LIMIT 2;
```

```
id	title	category	dist
4	red bike	vehicle	0
5	blue car	vehicle	0.023812934444366052
```

### 5.4 写入后立即可检索

seekdb 的增量索引让新写入的向量无需等待重建即可被检索到：

```sql
INSERT INTO doc_vectors VALUES (6,'green apple','food','[1.0,0.05,0.0,0.0]');

SELECT id, title, cosine_distance(embedding, '[1.0,0.0,0.0,0.0]') AS dist
FROM doc_vectors ORDER BY dist APPROXIMATE LIMIT 3;
```

```
id	title	dist
1	apple fruit	0
6	green apple	0.0012476612103002882
2	banana fruit	0.006116257407132508
```

### 5.5 对比：不带 APPROXIMATE 的精确计算

去掉 `APPROXIMATE` 就走逐行精确计算（可用来验证近似结果的召回），小数据量下结果应基本一致：

```sql
SELECT id, title, cosine_distance(embedding, '[1.0,0.0,0.0,0.0]') AS dist
FROM doc_vectors ORDER BY dist LIMIT 3;
```

常用距离函数：`l2_distance`、`cosine_distance`、`inner_product`、`negative_inner_product`。

### 5.6 清理

```sql
DROP TABLE IF EXISTS doc_vectors;
DROP TABLE IF EXISTS users;
DROP DATABASE IF EXISTS demo;
```

---

## 6. 故障排查

### 6.1 启动即退出：`libaio.so.1: cannot open shared object file`

原因：系统未安装 `libaio1`，seekdb 启动时找不到运行时库。`start.sh` 已通过 `LD_LIBRARY_PATH` 指向仓库自带依赖库，正常不会遇到。

若手动启动（例如直接调用 `sdb.py`），任选一种方式：

```bash
# 方式 A：用仓库自带依赖库，不改系统
export LD_LIBRARY_PATH="$PWD/deps/3rd/usr/local/oceanbase/deps/devel/lib:$LD_LIBRARY_PATH"

# 方式 B：安装系统包（Ubuntu 24.04+/Debian 13 用 libaio1t64）
sudo apt-get install -y libaio1
```

方式 A 必须在**启动进程的 shell** 中 export，子进程才能继承。

### 6.2 `wait-ready` 超时

先看实例日志：

```bash
base="${SEEKDB_BASE_DIR:-$PWD/build/dev-instance}"
tail -50 "$base/log/console.log"
ls "$base/log/"
```

常见原因是 6.1 的库缺失，或端口被占用。`wait-ready` 默认等待 180 秒，超时本身不代表新增错误。

### 6.3 链接阶段被 OOM kill

降低并发：`./build.py build -j4 seekdb`；或先提高 WSL 内存上限再重试。

### 6.4 `base-dir` 被拒绝

`sdb.py` 不允许把 HOME、当前目录及其父目录、文件系统根作为实例目录，也不接受符号链接。换一个普通子目录即可。

### 6.5 向量维度不匹配

`VECTOR(N)` 的 N 必须与插入/查询字面量中的元素个数一致。

### 6.6 `APPROXIMATE` 报错

该列没有向量索引，或索引不是 `Index_type=VECTOR`。先用 `SHOW INDEX FROM <table>;` 确认。

### 6.7 不使用脚本时的等价命令

```bash
python3 tools/deploy/sdb.py start \
  --binary build/bin/src/observer/seekdb \
  --base-dir "$PWD/build/dev-instance" --port 2881
python3 tools/deploy/sdb.py wait-ready \
  --client deps/3rd/u01/obclient/bin/obclient \
  --base-dir "$PWD/build/dev-instance" --port 2881
./deps/3rd/u01/obclient/bin/obclient -h127.0.0.1 -P2881 -uroot -A
python3 tools/deploy/sdb.py stop --base-dir "$PWD/build/dev-instance"
```

手动启动前需按 6.1 处理 `libaio.so.1`。

---

## 7. 相关文档

- 源码构建与运行：[`docs/developer-guide/en/build-and-run.md`](../developer-guide/en/build-and-run.md)
- 工具链准备：[`docs/developer-guide/en/toolchain.md`](../developer-guide/en/toolchain.md)
- MySQL 兼容测试：[`docs/developer-guide/en/mysqltest.md`](../developer-guide/en/mysqltest.md)
- 产品文档站：<https://docs.seekdb.ai/>
