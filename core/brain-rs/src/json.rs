//! A tiny JSON reader and writer, so the crate needs no dependencies. Object key order is kept.

#[derive(Clone, Debug, PartialEq)]
pub enum J { Null, Bool(bool), Num(f64), Str(String), Arr(Vec<J>), Obj(Vec<(String, J)>) }

impl J {
    pub fn get(&self, k: &str) -> Option<&J> { if let J::Obj(v) = self { v.iter().find(|(n, _)| n == k).map(|(_, x)| x) } else { None } }
    pub fn str(&self) -> Option<&str> { if let J::Str(s) = self { Some(s) } else { None } }
    pub fn num(&self) -> Option<f64> { if let J::Num(n) = self { Some(*n) } else { None } }
    pub fn bool(&self) -> Option<bool> { if let J::Bool(b) = self { Some(*b) } else { None } }
    pub fn arr(&self) -> Option<&Vec<J>> { if let J::Arr(a) = self { Some(a) } else { None } }
    pub fn first(&self) -> Option<(&String, &J)> { if let J::Obj(v) = self { v.first().map(|(k, x)| (k, x)) } else { None } }
}

pub struct P<'a> { pub b: &'a [u8], pub i: usize }
impl<'a> P<'a> {
    fn ws(&mut self) { while self.i < self.b.len() && (self.b[self.i] as char).is_whitespace() { self.i += 1; } }
    pub fn parse(&mut self) -> J {
        self.ws();
        match self.b[self.i] {
            b'{' => { self.i += 1; let mut v = vec![]; loop { self.ws(); if self.b[self.i] == b'}' { self.i += 1; break; }
                      let k = match self.parse() { J::Str(s) => s, _ => panic!("key") }; self.ws(); assert_eq!(self.b[self.i], b':'); self.i += 1;
                      let x = self.parse(); v.push((k, x)); self.ws(); if self.b[self.i] == b',' { self.i += 1; } } J::Obj(v) }
            b'[' => { self.i += 1; let mut v = vec![]; loop { self.ws(); if self.b[self.i] == b']' { self.i += 1; break; }
                      v.push(self.parse()); self.ws(); if self.b[self.i] == b',' { self.i += 1; } } J::Arr(v) }
            b'"' => { self.i += 1; let mut s = String::new(); loop { let c = self.b[self.i]; self.i += 1;
                      match c { b'"' => break, b'\\' => { let e = self.b[self.i]; self.i += 1; match e { b'n' => s.push('\n'), b't' => s.push('\t'), b'r' => s.push('\r'),
                                b'u' => { let h = std::str::from_utf8(&self.b[self.i..self.i + 4]).unwrap(); self.i += 4; s.push(char::from_u32(u32::from_str_radix(h, 16).unwrap()).unwrap_or('?')); }
                                o => s.push(o as char) } }
                                _ => { // copy a full UTF-8 sequence
                                    let start = self.i - 1; let mut end = self.i; while end < self.b.len() && (self.b[end] & 0xC0) == 0x80 { end += 1; }
                                    s.push_str(std::str::from_utf8(&self.b[start..end]).unwrap()); self.i = end; } } } J::Str(s) }
            b't' => { self.i += 4; J::Bool(true) } b'f' => { self.i += 5; J::Bool(false) } b'n' => { self.i += 4; J::Null }
            _ => { let s = self.i; while self.i < self.b.len() && matches!(self.b[self.i], b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9') { self.i += 1; }
                   J::Num(std::str::from_utf8(&self.b[s..self.i]).unwrap().parse().unwrap()) }
        }
    }
}


pub fn parse(text: &str) -> J { P { b: text.as_bytes(), i: 0 }.parse() }

pub fn to_string(j: &J) -> String {
    match j {
        J::Null => "null".into(), J::Bool(b) => b.to_string(),
        J::Num(n) => if n.fract() == 0.0 && n.abs() < 1e15 { format!("{}", *n as i64) } else { format!("{}", n) },
        J::Str(s) => { let mut o = String::from("\""); for c in s.chars() { match c { '"' => o.push_str("\\\""), '\\' => o.push_str("\\\\"), '\n' => o.push_str("\\n"), '\t' => o.push_str("\\t"), '\r' => o.push_str("\\r"), c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)), c => o.push(c) } } o.push('"'); o }
        J::Arr(a) => format!("[{}]", a.iter().map(to_string).collect::<Vec<_>>().join(",")),
        J::Obj(v) => format!("{{{}}}", v.iter().map(|(k, x)| format!("{}:{}", to_string(&J::Str(k.clone())), to_string(x))).collect::<Vec<_>>().join(",")),
    }
}
