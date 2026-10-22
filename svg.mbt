///|
/// World-space bounds for a shared drawing scale. Must contain all geometry.
pub(all) struct SvgBounds {
  min_x : Double
  min_y : Double
  max_x : Double
  max_y : Double
} derive(Debug)

///|
pub extend SvgBounds with @debug.Debug::{to_repr}

///|
pub(all) struct SvgOptions {
  width : Int32
  height : Int32
  padding : Double
  title : String
  show_points : Bool
  bounds : SvgBounds?
} derive(Debug)

///|
pub extend SvgOptions with @debug.Debug::{to_repr}

///|
pub fn SvgOptions::default() -> SvgOptions {
  {
    width: 720,
    height: 440,
    padding: 24.0,
    title: "CAD sketch",
    show_points: true,
    bounds: None,
  }
}

///|
fn svg_escape(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    match c {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '"' => out.write_string("&quot;")
      '\'' => out.write_string("&apos;")
      '\n' | '\r' | '\t' => out.write_string(" ")
      _ => {
        let n = c.to_int()
        if (n >= 32 && n <= 0xD7FF) ||
          (n >= 0xE000 && n <= 0xFFFD) ||
          n >= 0x10000 {
          out.write_char(c)
        } else {
          out.write_string("�")
        }
      }
    }
  }
  out.to_string()
}

///|
/// Export current stored geometry. Does not solve or apply candidate solutions.
/// Checks geometry and enabled constraint definitions using normal validation.
/// Lines are finite segments; circles keep their shape under uniform scaling.
pub fn Sketch::to_svg(
  self : Sketch,
  options~ : SvgOptions = SvgOptions::default(),
) -> Result[String, SketchError] {
  if options.width < 64 ||
    options.width > 4096 ||
    options.height < 96 ||
    options.height > 4096 ||
    !finite(options.padding) ||
    options.padding < 4.0 ||
    options.width.to_double() - 2.0 * options.padding <= 0.0 ||
    options.height.to_double() - 2.0 * options.padding - 32.0 <= 0.0 {
    return Err(
      InvalidOptions(
        "SVG dimensions must be 64..4096 by 96..4096 with room for padding and title",
      ),
    )
  }
  match self.validate() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let first = self.points.get(0).unwrap_or({ x: 0.0, y: 0.0, })
  let mut min_x = first.x
  let mut max_x = first.x
  let mut min_y = first.y
  let mut max_y = first.y
  let mut diameter = 0.0
  for p in self.points {
    min_x = if p.x < min_x { p.x } else { min_x }
    max_x = dmax(max_x, p.x)
    min_y = if p.y < min_y { p.y } else { min_y }
    max_y = dmax(max_y, p.y)
  }
  for c in self.circles {
    let p = self.points[c.center.index]
    min_x = if p.x - c.radius < min_x { p.x - c.radius } else { min_x }
    max_x = dmax(max_x, p.x + c.radius)
    min_y = if p.y - c.radius < min_y { p.y - c.radius } else { min_y }
    max_y = dmax(max_y, p.y + c.radius)
    diameter = dmax(diameter, 2.0 * c.radius)
  }
  match options.bounds {
    None => ()
    Some(b) => {
      if !finite(b.min_x) ||
        !finite(b.min_y) ||
        !finite(b.max_x) ||
        !finite(b.max_y) ||
        b.min_x >= b.max_x ||
        b.min_y >= b.max_y ||
        !finite(b.max_x - b.min_x) ||
        !finite(b.max_y - b.min_y) ||
        (
          self.points.length() > 0 &&
          (
            b.min_x > min_x ||
            b.max_x < max_x ||
            b.min_y > min_y ||
            b.max_y < max_y
          )
        ) {
        return Err(
          InvalidOptions(
            "SVG bounds must be finite, ordered and contain all stored geometry",
          ),
        )
      }
      min_x = b.min_x
      min_y = b.min_y
      max_x = b.max_x
      max_y = b.max_y
      for c in self.circles {
        let p = self.points[c.center.index]
        if c.radius > p.x - min_x ||
          c.radius > max_x - p.x ||
          c.radius > p.y - min_y ||
          c.radius > max_y - p.y {
          return Err(InvalidOptions("SVG bounds must contain full circles"))
        }
      }
    }
  }
  // Normalize before converting to pixels, including subnormal-sized geometry.
  // Radius contributes separately when center +/- radius rounds to the center.
  let world_width = dmax(max_x - min_x, diameter)
  let world_height = dmax(max_y - min_y, diameter)
  let span = dmax(world_width, world_height)
  let span = if span > 0.0 { span } else { 1.0 }
  let avail_width = options.width.to_double() - 2.0 * options.padding
  let avail_height = options.height.to_double() - 2.0 * options.padding - 32.0
  let pixels = if world_width >= world_height {
    let other = if world_height > 0.0 {
      avail_height / (world_height / span)
    } else {
      avail_width
    }
    if avail_width < other {
      avail_width
    } else {
      other
    }
  } else {
    let other = if world_width > 0.0 {
      avail_width / (world_width / span)
    } else {
      avail_height
    }
    if avail_height < other {
      avail_height
    } else {
      other
    }
  }
  let center_x = min_x / 2.0 + max_x / 2.0
  let center_y = min_y / 2.0 + max_y / 2.0
  let screen_x = (x : Double) => {
    options.width.to_double() / 2.0 + (x - center_x) / span * pixels
  }
  let screen_y = (y : Double) => {
    32.0 +
    (options.height.to_double() - 32.0) / 2.0 -
    (y - center_y) / span * pixels
  }
  let title = svg_escape(options.title)
  let out = StringBuilder()
  out.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\{options.width}\" height=\"\{options.height}\" viewBox=\"0 0 \{options.width} \{options.height}\" role=\"img\">\n",
  )
  out.write_string(
    "<title>\{title}</title>\n<desc>Current stored sketch geometry; X right, Y up. Export does not run the solver.</desc>\n",
  )
  out.write_string("<rect width=\"100%\" height=\"100%\" fill=\"#f5f7fb\"/>\n")
  out.write_string(
    "<text x=\"\{options.padding}\" y=\"28\" font-family=\"sans-serif\" font-size=\"17\" font-weight=\"600\" fill=\"#17243b\">\{title}</text>\n",
  )
  out.write_string(
    "<g id=\"lines\" fill=\"none\" stroke=\"#274b7a\" stroke-width=\"2\">\n",
  )
  for i, l in self.lines {
    let a = self.points[l.a.index]
    let b = self.points[l.b.index]
    out.write_string(
      "<line data-line=\"\{i}\" x1=\"\{screen_x(a.x)}\" y1=\"\{screen_y(a.y)}\" x2=\"\{screen_x(b.x)}\" y2=\"\{screen_y(b.y)}\"/>\n",
    )
  }
  out.write_string(
    "</g>\n<g id=\"circles\" fill=\"#e2f3f0\" stroke=\"#128574\" stroke-width=\"2\">\n",
  )
  for i, c in self.circles {
    let p = self.points[c.center.index]
    out.write_string(
      "<circle data-circle=\"\{i}\" cx=\"\{screen_x(p.x)}\" cy=\"\{screen_y(p.y)}\" r=\"\{(c.radius / span) * pixels}\"/>\n",
    )
  }
  out.write_string("</g>\n")
  if options.show_points {
    out.write_string("<g id=\"points\" fill=\"#d96d43\">\n")
    for i, p in self.points {
      out.write_string(
        "<circle data-point=\"\{i}\" cx=\"\{screen_x(p.x)}\" cy=\"\{screen_y(p.y)}\" r=\"3\"/>\n",
      )
    }
    out.write_string("</g>\n")
  }
  out.write_string("</svg>\n")
  Ok(out.to_string())
}
