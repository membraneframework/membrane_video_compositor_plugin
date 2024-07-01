use std::{
    collections::{BTreeMap, HashMap},
    sync::Arc,
    thread::sleep,
    time::Duration,
};

mod colour_converters;
pub mod math;
mod pipeline_common;
pub mod scene;
mod textures;
pub mod transformations;
mod videos;

use textures::*;
use videos::*;
use wgpu::{Adapter, Backends, Instance};

use crate::{elixir_bridge::RawVideo, errors::CompositorError};
pub use math::{Vec2d, Vertex};
pub use videos::{VideoPlacement, VideoProperties};

use self::{
    colour_converters::{RGBAToYUVConverter, YUVToRGBAConverter},
    scene::{Scene, VideoConfig},
    transformations::{filled_registry, Transformation},
};
use self::{pipeline_common::Sampler, transformations::registry::TransformationRegistry};

pub type VideoId = u32;

pub struct State {
    device: wgpu::Device,
    input_videos: BTreeMap<usize, InputVideo>,
    output_textures: OutputTextures,
    pipeline: wgpu::RenderPipeline,
    queue: wgpu::Queue,
    sampler: Sampler,
    single_texture_bind_group_layout: Arc<wgpu::BindGroupLayout>,
    all_yuv_textures_bind_group_layout: Arc<wgpu::BindGroupLayout>,
    yuv_to_rgba_converter: YUVToRGBAConverter,
    rgba_to_yuv_converter: RGBAToYUVConverter,
    output_stream_format: RawVideo,
    last_pts: Option<u64>,
    texture_transformation_pipelines: TransformationRegistry,
}

impl State {
    pub async fn new(output_stream_format: &RawVideo) -> Result<State, CompositorError> {
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
            backends: wgpu::Backends::all(),
            ..Default::default()
        });
        let adapter = Self::request_adapter(&instance).await;

        let (device, queue) = adapter
            .request_device(
                &wgpu::DeviceDescriptor {
                    label: Some("device"),
                    required_features: wgpu::Features::empty(),
                    required_limits: wgpu::Limits::default(),
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
            output_stream_format.width.get(),
            output_stream_format.height.get(),
            &single_texture_bind_group_layout,
        );

        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            min_filter: wgpu::FilterMode::Linear,
            mag_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Linear,
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
                    blend: Some(wgpu::BlendState::ALPHA_BLENDING),
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

        let texture_transformation_pipelines =
            filled_registry(&device, &single_texture_bind_group_layout);

        Ok(Self {
            device,
            input_videos,
            output_textures,
            pipeline,
            queue,
            sampler: Sampler {
                _sampler: sampler,
                bind_group: sampler_bind_group,
            },
            single_texture_bind_group_layout: Arc::new(single_texture_bind_group_layout),
            all_yuv_textures_bind_group_layout: Arc::new(all_yuv_textures_bind_group_layout),
            yuv_to_rgba_converter,
            rgba_to_yuv_converter,
            output_stream_format: *output_stream_format,
            last_pts: None,
            texture_transformation_pipelines,
        })
    }

    pub async fn request_adapter(instance: &Instance) -> Adapter {
        // On some platforms adapter requests fail unexpectedly.
        // Therefore, it's requested multiple times here.
        const ADAPTER_REQUEST_RETRIES_COUNT: u32 = 10;

        for retry in 0..ADAPTER_REQUEST_RETRIES_COUNT {
            let some_adapter = instance
                .request_adapter(&wgpu::RequestAdapterOptions {
                    compatible_surface: None,
                    force_fallback_adapter: false,
                    power_preference: wgpu::PowerPreference::HighPerformance,
                })
                .await;

            match some_adapter {
                Some(adapter) => {
                    return adapter;
                }
                None => {
                    println!("{} adapter requests failed.", retry + 1);
                    sleep(Duration::from_millis(1));
                }
            }

            println!(
                "Available Vulcan adapters: {:#?}",
                instance.enumerate_adapters(Backends::VULKAN)
            );
        }

        panic!(
            "Failed to request adapter after {} retries",
            ADAPTER_REQUEST_RETRIES_COUNT
        );
    }

    pub fn set_videos(
        &mut self,
        scene: Scene,
        video_resolutions: HashMap<VideoId, Vec2d<u32>>,
    ) -> Result<(), CompositorError> {
        self.input_videos = BTreeMap::new();

        for (
            video_id,
            VideoConfig {
                placement,
                transformations: texture_transformations,
            },
        ) in scene.video_configs
        {
            match video_resolutions.get(&video_id) {
                Some(input_resolution) => {
                    self.add_video(
                        video_id as usize,
                        VideoProperties {
                            input_resolution: *input_resolution,
                            placement,
                        },
                        texture_transformations,
                    )?;
                }
                None => return Err(CompositorError::BadVideoIndex(video_id as usize)),
            }
        }

        Ok(())
    }

    fn add_video(
        &mut self,
        idx: usize,
        base_properties: VideoProperties,
        texture_transformations: Vec<Box<dyn Transformation>>,
    ) -> Result<(), CompositorError> {
        if self.input_videos.contains_key(&idx) {
            return Err(CompositorError::VideoIndexAlreadyTaken(idx));
        }

        self.input_videos.insert(
            idx,
            InputVideo::new(
                &self.device,
                self.single_texture_bind_group_layout.clone(),
                &self.all_yuv_textures_bind_group_layout,
                base_properties,
                texture_transformations,
            ),
        );

        Ok(())
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
                frame,
                pts,
                self.last_pts,
                &self.texture_transformation_pipelines,
            );
        Ok(())
    }

    pub fn all_frames_ready(&self) -> bool {
        !self.input_videos.is_empty()
            && self.input_videos.values().any(|v| v.front_pts().is_some())
            && self
                .input_videos
                .values()
                .all(|v| v.is_frame_ready(self.frame_interval()))
    }

    /// This returns the pts of the new frame
    pub async fn draw_into(&mut self, output_buffer: &mut [u8]) -> u64 {
        let interval = self.frame_interval();
        self.input_videos
            .values_mut()
            .for_each(|v| v.remove_stale_frames(interval));

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("encoder"),
            });

        let mut pts = 0;
        let mut rendered_video_ids = Vec::new();

        let mut videos_sorted_by_z_value = self.input_videos.iter_mut().collect::<Vec<_>>();
        videos_sorted_by_z_value.sort_by(|(_, vid1), (_, vid2)| {
            vid2.transformed_properties()
                .placement
                .z
                .total_cmp(&vid1.transformed_properties().placement.z)
        });

        {
            let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("render pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &self.output_textures.rgba_texture.texture.view,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store: wgpu::StoreOp::Store,
                    },
                    resolve_target: None,
                })],
                depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment {
                    view: &self.output_textures.depth_texture.view,
                    depth_ops: Some(wgpu::Operations {
                        load: wgpu::LoadOp::Clear(1.0),
                        store: wgpu::StoreOp::Store,
                    }),
                    stencil_ops: None,
                }),
                occlusion_query_set: None,
                timestamp_writes: None,
            });

            render_pass.set_pipeline(&self.pipeline);
            render_pass.set_bind_group(1, &self.sampler.bind_group, &[]);

            for (&id, video) in videos_sorted_by_z_value.iter_mut() {
                match video.draw(
                    &self.queue,
                    &mut render_pass,
                    &self.output_stream_format,
                    interval,
                ) {
                    DrawResult::Rendered(new_pts) => {
                        pts = pts.max(new_pts);
                        rendered_video_ids.push(id);
                    }
                    DrawResult::NotRendered => {}
                }
            }
        }

        rendered_video_ids
            .iter()
            .for_each(|id| self.input_videos.get_mut(id).unwrap().pop_frame());

        self.queue.submit(Some(encoder.finish()));

        self.output_textures.transfer_content_to_buffers(
            &self.device,
            &self.queue,
            &self.rgba_to_yuv_converter,
        );

        self.output_textures
            .download(&self.device, output_buffer)
            .await;

        self.last_pts = Some(pts);

        pts
    }

    /// This is in nanoseconds
    pub fn frame_time(&self) -> f64 {
        self.output_stream_format.framerate.1.get() as f64
            / self.output_stream_format.framerate.0.get() as f64
            * 1_000_000_000.0
    }

    pub fn frame_interval(&self) -> Option<(u64, u64)> {
        self.last_pts.map(|start| {
            (
                start,
                (((start as f64 + self.frame_time()) / 1_000_000.0).ceil() * 1_000_000.0) as u64,
            )
        })
    }

    #[allow(unused)]
    pub fn dump_queue_state(&self) {
        println!("[rust compositor queue dump]");
        println!(
            "  interval: {:?}, frame_time: {}",
            self.frame_interval(),
            self.frame_time()
        );
        for (key, val) in &self.input_videos {
            println!("  vid {key} => front pts {:?}", val.front_pts());
        }
    }
}
