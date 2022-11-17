#![allow(clippy::needless_borrow)]

#[derive(Debug, rustler::NifStruct, Clone)]
#[module = "Membrane.VideoCompositor.RustStructs.RawVideo"]
pub struct ElixirRawVideo {
    pub width: u32,
    pub height: u32,
    pub pixel_format: rustler::Atom,
    pub framerate: (u64, u64),
}

#[derive(Debug, rustler::NifStruct)]
#[module = "Membrane.VideoCompositor.RustStructs.VideoProperties"]
pub struct VideoProperties {
    pub x: u32,
    pub y: u32,
    pub z: f32,
    pub scale: f64,
}
