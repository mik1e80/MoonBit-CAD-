///|
/// Solve min ||J dx + r||^2 + lambda ||D dx||^2 by Givens QR of
/// [J D^-1; sqrt(lambda) I]. Avoid forming the normal equations J^T J.
fn damped_step(
  jacobian : Array[Array[Double]],
  residual : Array[Double],
  n : Int32,
  lambda : Double,
) -> Array[Double]? {
  let m = jacobian.length()
  let scales = Array::make(n, 0.0)
  for row in jacobian {
    for j = 0; j < n; j = j + 1 {
      scales[j] = @math.hypot(scales[j], row[j])
    }
  }
  for j = 0; j < n; j = j + 1 {
    if scales[j] < 1.0e-14 {
      scales[j] = 1.0
    }
  }
  let a = Array::makei(m + n, i => {
    Array::makei(n, j => {
      if i < m {
        jacobian[i][j] / scales[j]
      } else if i - m == j {
        lambda.sqrt()
      } else {
        0.0
      }
    })
  })
  let b = Array::makei(m + n, i => if i < m { -residual[i] } else { 0.0 })
  for j = 0; j < n; j = j + 1 {
    for i = m + n - 1; i > j; i = i - 1 {
      if a[i][j] != 0.0 {
        let norm = @math.hypot(a[j][j], a[i][j])
        let c = a[j][j] / norm
        let s = a[i][j] / norm
        for k = j; k < n; k = k + 1 {
          let upper = a[j][k]
          let lower = a[i][k]
          a[j][k] = c * upper + s * lower
          a[i][k] = -s * upper + c * lower
        }
        let upper = b[j]
        b[j] = c * upper + s * b[i]
        b[i] = -s * upper + c * b[i]
      }
    }
  }
  let z = Array::make(n, 0.0)
  for i = n - 1; i >= 0; i = i - 1 {
    let mut rhs = b[i]
    for j = i + 1; j < n; j = j + 1 {
      rhs = rhs - a[i][j] * z[j]
    }
    if a[i][i].abs() < 1.0e-100 {
      return None
    }
    z[i] = rhs / a[i][i]
  }
  let out = Array::makei(n, i => z[i] / scales[i])
  if out.any(x => !finite(x)) {
    None
  } else {
    Some(out)
  }
}

///|
/// Local numerical rank, with row normalization and complete pivoting.
/// This is a first-order diagnostic, not a global rigidity certificate.
fn numerical_rank(
  j : Array[Array[Double]],
  n : Int32,
  tolerance : Double,
) -> Int32 {
  let a = j.map(row => {
    let scale = max_abs(row)
    if scale == 0.0 {
      row.copy()
    } else {
      row.map(x => x / scale)
    }
  })
  let m = a.length()
  let mut rank = 0
  while rank < m && rank < n {
    let mut best = 0.0
    let mut pi = rank
    let mut pj = rank
    for i = rank; i < m; i = i + 1 {
      for k = rank; k < n; k = k + 1 {
        if a[i][k].abs() > best {
          best = a[i][k].abs()
          pi = i
          pj = k
        }
      }
    }
    if best <= tolerance {
      break
    }
    let tmp = a[rank]
    a[rank] = a[pi]
    a[pi] = tmp
    for row in a {
      let t = row[rank]
      row[rank] = row[pj]
      row[pj] = t
    }
    for i = rank + 1; i < m; i = i + 1 {
      let factor = a[i][rank] / a[rank][rank]
      for k = rank + 1; k < n; k = k + 1 {
        a[i][k] = a[i][k] - factor * a[rank][k]
      }
      a[i][rank] = 0.0
    }
    rank = rank + 1
  }
  rank
}
