/*
 * GLRenderSystem.h
 *
 * Copyright (c) 2015 Lukas Hermanns. All rights reserved.
 * Licensed under the terms of the BSD 3-Clause license (see LICENSE.txt).
 */

#ifndef LLGL_GL_RENDER_SYSTEM_H
#define LLGL_GL_RENDER_SYSTEM_H


#include <LLGL/RenderSystem.h>
#include "Ext/GLExtensionRegistry.h"
#include "../ContainerTypes.h"

#include "Command/GLCommandQueue.h"
#include "Command/GLCommandBuffer.h"
#include "GLSwapChain.h"
#include "Platform/GLContextManager.h"

#include "Buffer/GLBuffer.h"
#include "Buffer/GLBufferArray.h"

#include "Shader/GLShader.h"
#include "Shader/GLShaderProgram.h"

#include "Texture/GLTexture.h"
#include "Texture/GLSampler.h"
#include "Texture/GLRenderTarget.h"
#ifdef LLGL_GL_ENABLE_OPENGL2X
#   include "Texture/GL2XSampler.h"
#endif

#include "RenderState/GLQueryHeap.h"
#include "RenderState/GLFence.h"
#include "RenderState/GLRenderPass.h"
#include "RenderState/GLPipelineLayout.h"
#include "RenderState/GLPipelineState.h"
#include "RenderState/GLResourceHeap.h"

#include <string>
#include <memory>
#include <vector>
#include <set>


namespace LLGL
{


class GLRenderSystem final : public RenderSystem
{

    public:

        #include <LLGL/Backend/RenderSystem.inl>

    public:

        GLRenderSystem(const RenderSystemDescriptor& renderSystemDesc);
        ~GLRenderSystem();

    private:

        void CreateGLContextDependentDevices(GLStateManager& stateManager);

        void EnableDebugCallback(bool enable = true);

        void QueryRendererInfo();
        void QueryRenderingCaps();

        GLBuffer* CreateGLBuffer(const BufferDescriptor& desc, const void* initialData);

        void ValidateGLTextureType(const TextureType type);

    private:

        /* ----- Hardware object containers ----- */

        GLContextManager                    contextMngr_;
        bool                                debugContext_   = false;

        HWObjectContainer<GLSwapChain>      swapChains_;
        HWObjectInstance<GLCommandQueue>    commandQueue_;
        HWObjectContainer<GLCommandBuffer>  commandBuffers_;
        HWObjectContainer<GLBuffer>         buffers_;
        HWObjectContainer<GLBufferArray>    bufferArrays_;
        HWObjectContainer<GLTexture>        textures_;
        HWObjectContainer<GLSampler>        samplers_;
        #ifdef LLGL_GL_ENABLE_OPENGL2X
        HWObjectContainer<GL2XSampler>      samplersGL2X_;
        #endif
        HWObjectContainer<GLRenderPass>     renderPasses_;
        HWObjectContainer<GLRenderTarget>   renderTargets_;
        HWObjectContainer<GLShader>         shaders_;
        HWObjectContainer<GLPipelineLayout> pipelineLayouts_;
        HWObjectContainer<GLPipelineState>  pipelineStates_;
        HWObjectContainer<GLResourceHeap>   resourceHeaps_;
        HWObjectContainer<GLQueryHeap>      queryHeaps_;
        HWObjectContainer<GLFence>          fences_;

};


} // /namespace LLGL


#endif



// ================================================================================
