use std::{collections::BTreeMap, fmt::Display};

mod colour_converters;
mod textures;
mod videos;

use textures::*;
use videos::*;

use crate::errors::CompositorError;
pub use videos::VideoPosition;

use self::colour_converters::{RGBAToYUVConverter, YUVToRGBAConverter};

#[derive(Debug, Clone, Copy)]
#[repr(C)]
/// A point in 2D space
pub struct Point<T> {
    pub x: T,
    pub y: T,
}

impl<T: Display> Display for Point<T> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "({}, {})", self.x, self.y)
    }
}

#[repr(C)]
#[derive(Debug, Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub struct Vertex {
    pub position: [f32; 3],
    pub texture_coords: [f32; 2],
}

impl Vertex {
    const LAYOUT: wgpu::VertexBufferLayout<'static> = wgpu::VertexBufferLayout {
        array_stride: std::mem::size_of::<Vertex>() as u64,
        step_mode: wgpu::VertexStepMode::Vertex,
        attributes: &wgpu::vertex_attr_array![0 => Float32x3, 1 => Float32x2],
    };
}

struct Sampler {
    _sampler: wgpu::Sampler,
    bind_group: wgpu::BindGroup,
}

pub struct State {
    device: wgpu::Device,
    input_videos: BTreeMap<usize, InputVideo>,
    output_textures: OutputTextures,
    pipeline: wgpu::RenderPipeline,
    queue: wgpu::Queue,
    sampler: Sampler,
    single_texture_bind_group_layout: wgpu::BindGroupLayout,
    all_yuv_textures_bind_group_layout: wgpu::BindGroupLayout,
    yuv_to_rgba_converter: YUVToRGBAConverter,
    rgba_to_yuv_converter: RGBAToYUVConverter,
    output_caps: crate::RawVideo,
    last_pts: Option<u64>,
}

impl State {
    pub async fn new(output_caps: &crate::RawVideo) -> State {
        let instance = wgpu::Instance::new(wgpu::Backends::all());
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                compatible_surface: None,
                force_fallback_adapter: false,
                power_preference: wgpu::PowerPreference::HighPerformance,
            })
            .await
            .unwrap();

        let (device, queue) = adapter
            .request_device(
                &wgpu::DeviceDescriptor {
                    label: Some("device"),
                    features: wgpu::Features::empty(),
                    limits: wgpu::Limits::default(),
                },
                None,
            )
            .await
            .unwrap();

        let single_texture_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("single texture bind group layout"),
                entries: &[wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    count: None,
                }],
            });

        let all_yuv_textures_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("yuv all textures bind group layout"),
                entries: &[
                    wgpu::BindGroupLayoutEntry {
                        binding: 0,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: true },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 1,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: true },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 2,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: true },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        count: None,
                    },
                ],
            });

        let input_videos = BTreeMap::new();

        let output_textures = OutputTextures::new(
            &device,
            output_caps.width,
            output_caps.height,
            &single_texture_bind_group_layout,
        );

        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            min_filter: wgpu::FilterMode::Nearest,
            mag_filter: wgpu::FilterMode::Nearest,
            mipmap_filter: wgpu::FilterMode::Nearest,
            ..Default::default()
        });

        let sampler_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("sampler bind group layout"),
                entries: &[wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    count: None,
                }],
            });

        let sampler_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("sampler bind group"),
            layout: &sampler_bind_group_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: wgpu::BindingResource::Sampler(&sampler),
            }],
        });

        let shader_module = device.create_shader_module(wgpu::include_wgsl!("shader.wgsl"));

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("pipeline layout"),
            bind_group_layouts: &[
                &single_texture_bind_group_layout,
                &sampler_bind_group_layout,
            ],
            push_constant_ranges: &[],
        });

        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("pipeline"),
            layout: Some(&pipeline_layout),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                front_face: wgpu::FrontFace::Ccw,
                cull_mode: Some(wgpu::Face::Back),
                strip_index_format: None,
                polygon_mode: wgpu::PolygonMode::Fill,
                unclipped_depth: false,
                conservative: false,
            },
            vertex: wgpu::VertexState {
                module: &shader_module,
                entry_point: "vs_main",
                buffers: &[Vertex::LAYOUT],
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader_module,
                entry_point: "fs_main",
                targets: &[Some(wgpu::ColorTargetState {
                    blend: None,
                    write_mask: wgpu::ColorWrites::all(),
                    format: wgpu::TextureFormat::Rgba8Unorm,
                })],
            }),
            multisample: wgpu::MultisampleState {
                count: 1,
                mask: !0,
                alpha_to_coverage_enabled: false,
            },
            multiview: None,
            depth_stencil: Some(wgpu::DepthStencilState {
                format: wgpu::TextureFormat::Depth32Float,
                depth_write_enabled: true,
                depth_compare: wgpu::CompareFunction::Less,
                stencil: wgpu::StencilState::default(),
                bias: wgpu::DepthBiasState::default(),
            }),
        });

        let yuv_to_rgba_converter =
            YUVToRGBAConverter::new(&device, &all_yuv_textures_bind_group_layout);
        let rgba_to_yuv_converter =
            RGBAToYUVConverter::new(&device, &single_texture_bind_group_layout);

        Self {
            device,
            input_videos,
            output_textures,
            pipeline,
            queue,
            sampler: Sampler {
                _sampler: sampler,
                bind_group: sampler_bind_group,
            },
            single_texture_bind_group_layout,
            all_yuv_textures_bind_group_layout,
            yuv_to_rgba_converter,
            rgba_to_yuv_converter,
            output_caps: output_caps.clone(),
            last_pts: None,
        }
    }

    pub fn upload_texture(
        &mut self,
        idx: usize,
        frame: &[u8],
        pts: u64,
    ) -> Result<(), CompositorError> {
        self.input_videos
            .get_mut(&idx)
            .ok_or(CompositorError::BadVideoIndex(idx))?
            .upload_data(
                &self.device,
                &self.queue,
                &self.yuv_to_rgba_converter,
                &self.single_texture_bind_group_layout,
                frame,
                pts,
                self.last_pts,
            );
        Ok(())
    }

    pub fn all_frames_ready(&self, frame_period: f64) -> bool {
        let start_pts = self.last_pts;
        let end_pts = start_pts.map(|pts| (pts as f64 + frame_period) as u64);

        self.input_videos.values().all(|v| {
            v.front_pts().is_some()
                && (start_pts.is_none()
                    || (start_pts.unwrap() <= v.front_pts().unwrap()
                        && v.front_pts().unwrap() < end_pts.unwrap()))
        })
    }

    /// This returns the pts of the new frame
    pub async fn draw_into(&mut self, output_buffer: &mut [u8]) -> u64 {
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("encoder"),
            });

        let mut pts = 0;

        {
            let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("render pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &self.output_textures.rgba_texture.texture.view,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store: true,
                    },
                    resolve_target: None,
                })],
                depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment {
                    view: &self.output_textures.depth_texture.view,
                    depth_ops: Some(wgpu::Operations {
                        load: wgpu::LoadOp::Clear(1.0),
                        store: true,
                    }),
                    stencil_ops: None,
                }),
            });

            render_pass.set_pipeline(&self.pipeline);
            render_pass.set_bind_group(1, &self.sampler.bind_group, &[]);

            for video in self.input_videos.values_mut() {
                if let Some(new_pts) = video.draw(&self.queue, &mut render_pass, &self.output_caps)
                {
                    pts = pts.max(new_pts);
                }
            }
        }

        self.queue.submit(Some(encoder.finish()));

        self.output_textures.transfer_content_to_buffers(
            &self.device,
            &self.queue,
            &self.rgba_to_yuv_converter,
        );

        self.output_textures
            .download(&self.device, output_buffer)
            .await;

        pts
    }

    pub fn add_video(&mut self, idx: usize, position: VideoPosition) {
        self.input_videos.insert(
            idx,
            InputVideo::new(
                &self.device,
                &self.single_texture_bind_group_layout,
                &self.all_yuv_textures_bind_group_layout,
                position,
            ),
        );
    }

    pub fn remove_video(&mut self, idx: usize) -> Result<(), CompositorError> {
        self.input_videos
            .remove(&idx)
            .ok_or(CompositorError::BadVideoIndex(idx))?;
        Ok(())
    }
}
