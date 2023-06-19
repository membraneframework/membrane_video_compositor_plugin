use std::{any::Any, sync::Arc};

use crate::{plugins::CustomProcessor, WgpuContext};

use super::PluginRegistryKey;

// Question to the reviewers: should the example below be in the finished documentation? Should it be
//                            kept until the end of the plugins PR?
//
// Question to the reviewers, but for later: There are a couple of syntax sugar possibilities for the initialization described below.
//                                           We could have a proc macro, a macro_rules macro, or possibly even leave it as-is but
//                                           generate the boilerplate. Which one should we use?
// NOTE: Send + Sync is necessary to store these in the compositor's state later.
//       'static is necessary for sending across elixir
/// # Examples
/// initialization might look like this:
/// ```no_run
/// # use std::sync::Arc;
/// # use membrane_video_compositor_common::WgpuContext;
/// use membrane_video_compositor_common::elixir_transfer::{StructElixirPacket, TransformationElixirPacket};
/// use membrane_video_compositor_common::plugins::{CustomProcessor, PluginRegistryKey, transformation::Transformation};
/// # struct CustomTransformation{}
/// # struct CustomTransformationArg{}
/// #
/// # impl CustomProcessor for CustomTransformation {
/// #     type Arg = CustomTransformationArg;
/// #     fn registry_key() -> PluginRegistryKey<'static>
/// #     where
/// #         Self: Sized
/// #     {
/// #         PluginRegistryKey("custom transformation")
/// #     }
/// #
/// #     fn registry_key_dyn(&self) -> PluginRegistryKey<'static> {
/// #         PluginRegistryKey("custom transformation")
/// #     }
/// # }
/// #
/// # impl Transformation for CustomTransformation {
/// #     fn do_stuff(&self, arg: &Self::Arg) {}
/// #     fn new(ctx: Arc<WgpuContext>) -> Self
/// #     where
/// #         Self: Sized {
/// #         Self {}
/// #     }
/// # }
///
/// #[rustler::nif]
/// fn get_transformation(ctx: StructElixirPacket<WgpuContext>) -> TransformationElixirPacket {
///     let ctx = unsafe { ctx.decode() };
///     unsafe { TransformationElixirPacket::encode(CustomTransformation::new(ctx)) }
/// }
/// ```
pub trait Transformation: CustomProcessor {
    fn do_stuff(&self, arg: &Self::Arg);

    fn new(ctx: Arc<WgpuContext>) -> Self
    where
        Self: Sized;
}

pub trait UntypedTransformation: Send + Sync + 'static {
    fn registry_key(&self) -> PluginRegistryKey<'static>;
    fn do_stuff(&self, arg: &dyn Any);
}

impl<T: Transformation> UntypedTransformation for T {
    fn registry_key(&self) -> PluginRegistryKey<'static> {
        assert_eq!(
            <Self as CustomProcessor>::registry_key(),
            self.registry_key_dyn()
        );
        <Self as CustomProcessor>::registry_key()
    }

    fn do_stuff(&self, arg: &dyn Any) {
        self.do_stuff(
            arg.downcast_ref().unwrap_or_else(|| panic!(
                "in {}, expected a successful cast to user-defined Arg type. Something went seriously wrong here.", 
                module_path!()
            ))
        )
    }
}