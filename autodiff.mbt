///|
/// Forward-mode automatic differentiation. No finite-difference step size.
priv struct Jet {
  v : Double
  d : Array[Double]
}

///|
fn constant(v : Double, n : Int) -> Jet {
  { v, d: Array::make(n, 0.0), }
}

///|
fn variable(v : Double, i : Int, n : Int) -> Jet {
  let d = Array::make(n, 0.0)
  d[i] = 1.0
  { v, d, }
}

///|
fn Jet::plus(a : Jet, b : Jet) -> Jet {
  { v: a.v + b.v, d: Array::makei(a.d.length(), i => a.d[i] + b.d[i]), }
}

///|
fn Jet::minus(a : Jet, b : Jet) -> Jet {
  { v: a.v - b.v, d: Array::makei(a.d.length(), i => a.d[i] - b.d[i]), }
}

///|
fn Jet::times(a : Jet, b : Jet) -> Jet {
  {
    v: a.v * b.v,
    d: Array::makei(a.d.length(), i => a.d[i] * b.v + a.v * b.d[i]),
  }
}

///|
fn Jet::scale(a : Jet, k : Double) -> Jet {
  { v: a.v * k, d: a.d.map(x => x * k), }
}

///|
fn Jet::offset(a : Jet, k : Double) -> Jet {
  { v: a.v + k, d: a.d, }
}

///|
fn Jet::divide(a : Jet, b : Jet) -> Jet {
  let v = a.v / b.v
  { v, d: Array::makei(a.d.length(), i => (a.d[i] - v * b.d[i]) / b.v), }
}

///|
fn jet_norm(x : Jet, y : Jet) -> Jet {
  let v = @math.hypot(x.v, y.v)
  if v == 0.0 {
    constant(0.0, x.d.length())
  } else {
    {
      v,
      d: Array::makei(x.d.length(), i => x.v / v * x.d[i] + y.v / v * y.d[i]),
    }
  }
}

///|
fn jet_angle(y : Jet, x : Jet) -> Jet {
  let denom = x.v * x.v + y.v * y.v
  {
    v: @math.atan2(y.v, x.v),
    d: Array::makei(x.d.length(), i => (x.v * y.d[i] - y.v * x.d[i]) / denom),
  }
}

///|
fn jet_dot(ax : Jet, ay : Jet, bx : Jet, by : Jet) -> Jet {
  ax.times(bx).plus(ay.times(by))
}

///|
fn jet_cross(ax : Jet, ay : Jet, bx : Jet, by : Jet) -> Jet {
  ax.times(by).minus(ay.times(bx))
}
