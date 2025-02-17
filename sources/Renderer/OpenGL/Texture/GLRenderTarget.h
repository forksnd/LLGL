/*
 * GLRenderTarget.h
 *
 * Copyright (c) 2015 Lukas Hermanns. All rights reserved.
 * Licensed under the terms of the BSD 3-Clause license (see LICENSE.txt).
 */

#ifndef LLGL_GL_RENDER_TARGET_H
#define LLGL_GL_RENDER_TARGET_H


#include <LLGL/RenderTarget.h>
#include <LLGL/Container/SmallVector.h>
#include "GLFramebuffer.h"
#include "GLRenderbuffer.h"
#include "GLTexture.h"
#include <functional>
#include <vector>
#include <memory>


namespace LLGL
{


class GLStateManager;

class GLRenderTarget final : public RenderTarget
{

    public:

        #include <LLGL/Backend/RenderTarget.inl>

    public:

        void SetName(const char* name) override;

    public:

        GLRenderTarget(const RenderTargetDescriptor& desc);
        ~GLRenderTarget();

        // Blits the multi-sample framebuffer onto the default framebuffer.
        void ResolveMultisampled(GLStateManager& stateMngr);

        // Blits the specified color attachment from the framebuffer onto the screen.
        void ResolveMultisampledIntoBackbuffer(GLStateManager& stateMngr, std::uint32_t colorTarget);

        // Sets the draw buffers for the currently bound FBO.
        void SetDrawBuffers();

        // Returns the primary FBO.
        inline const GLFramebuffer& GetFramebuffer() const
        {
            return framebuffer_;
        }

    private:

        void CreateFramebufferWithAttachments(const RenderTargetDescriptor& desc);
        void CreateFramebufferWithNoAttachments();

        void BuildColorAttachment(const AttachmentDescriptor& attachmentDesc, std::uint32_t colorTarget);
        void BuildResolveAttachment(const AttachmentDescriptor& attachmentDesc, std::uint32_t colorTarget);
        void BuildDepthStencilAttachment(const AttachmentDescriptor& attachmentDesc);

        void BuildAttachmentWithTexture(GLenum binding, const AttachmentDescriptor& attachmentDesc);
        void BuildAttachmentWithRenderbuffer(GLenum binding, Format format);

        void CreateAndAttachRenderbuffer(GLenum binding, GLenum internalFormat);

        GLenum AllocColorAttachmentBinding(std::uint32_t colorTarget);
        GLenum AllocResolveAttachmentBinding(std::uint32_t colorTarget);
        GLenum AllocDepthStencilAttachmentBinding(const Format format);

    private:

        GLint                       resolution_[2];

        GLFramebuffer               framebuffer_;                       // Primary FBO
        GLFramebuffer               framebufferResolve_;                // Secondary FBO to resolve multi-sampled FBO into

        /*
        For multi-sampled render targets we also need a renderbuffer for each attached texture.
        Otherwise we would need multi-sampled textures (e.g. "glTexImage2DMultisample")
        which is only supported since OpenGL 3.2+, but renderbuffers are supported since OpenGL 3.0+.
        */
        std::vector<GLRenderbuffer> renderbuffers_;

        SmallVector<GLenum, 2>      drawBuffers_;                       // Values for glDrawBuffers for the primary FBO
        SmallVector<GLenum, 2>      drawBuffersResolve_;                // Values for glDrawBuffers for the resolve FBO

        GLint                       samples_                = 1;
        GLenum                      depthStencilBinding_    = 0;        // Equivalent of drawBuffers but for depth-stencil

        const RenderPass*           renderPass_             = nullptr;

};


} // /namespace LLGL


#endif



// ================================================================================
