// The running command's thread (ui/capsules.luau): Bioma's rate thread
// (genoma/components/rate_thread.wgsl there) stood upright. A hairline down
// the margin, and over it round dashes in the primary running down it as
// fast as the program writes, still when it writes nothing.
//
// The numbers:
//   0      speed, logical units a second (0 still)
//   1      the dashes' thickness, logical units
//   2      the hairline's thickness
//   4…7    the hairline's colour, straight alpha
//   8…11   the dashes' colour, straight alpha

fn shade(p: vec2<f32>) -> vec4<f32> {
    let speed = value(0);
    let thick = value(1);
    let hair = value(2);
    let line = vec4<f32>(value(4), value(5), value(6), value(7));
    let dash = vec4<f32>(value(8), value(9), value(10), value(11));
    let mid = shader.size.x * 0.5;
    let aa = 0.5 / shader.scale;
    // The hairline down the middle.
    let h = 1.0 - smoothstep(hair * 0.5 - aa, hair * 0.5 + aa, abs(p.x - mid));
    var out = vec4<f32>(line.rgb * line.a * h, line.a * h);
    // Dashes two strokes long with round caps, four strokes between, as
    // Bioma's, moving down.
    let len = thick * 2.0;
    let period = thick * 6.0;
    let y = p.y - shader.time * speed;
    let local = y - floor(y / period) * period;
    let d = length(vec2<f32>(p.x - mid, max(abs(local - len * 0.5) - len * 0.5, 0.0))) - thick * 0.5;
    let a = dash.a * (1.0 - smoothstep(-aa, aa, d));
    out = vec4<f32>(dash.rgb * a + out.rgb * (1.0 - a), a + out.a * (1.0 - a));
    return out;
}
