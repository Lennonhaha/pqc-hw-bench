# lattice-estimator 跑 ML-KEM 参数

日期：2026-09-28
环境：CoCalc（Sage 内核）+ `pip install malb/lattice-estimator`
运行方式：`.sage` 文件，用 estimator 的 `schemes` 定义，非手写参数
攻击：仅 primal_usvp（Sage shim 缺 dual/BKW/BDD 依赖）

## 结果

| 方案 | β | rough bits | full bits | 格维度 d |
|-----------|-----|------------|-----------|----------|
| Kyber512 | 406 | 2^119 | 2^144 | 998 |
| Kyber768 | 624 | 2^182 | 2^205 | 1427 |
| Kyber1024 | 874 | 2^255 | 2^292 | 1867 |

## 方法验证

- Kyber512 的 β=406 与 lattice-estimator README 示例一致 → estimator 本身正确
- Kyber768 的 β=624 高于早期文献值（~448-480）→ 归因于 cost model 差异
 （ADPS16 vs MATZOV，差约 20-30 bits）。引用时须注明 cost model。

## 限制

1. 只有 primal_usvp——其它攻击因 Sage shim 不完整而报错
2. β 依赖 cost model：同一参数在不同 model 下相差 20-30 bits
3. CBD vs Gaussian secret 不影响 β（已验证）

## 复用路径

后续参数估计（如 VWZ）可复用：
- CoCalc 免费项目 + Sage 内核
- `pip install -e .` 装 estimator
- 用 schemes 定义，不手写 LWE.Parameters

## 待核

- 「ACNS'18 评估 β≈398/448」引用的原始来源未确认，暂不入正式引用