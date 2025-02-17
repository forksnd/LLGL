/*
 * MTTexture.mm
 *
 * Copyright (c) 2015 Lukas Hermanns. All rights reserved.
 * Licensed under the terms of the BSD 3-Clause license (see LICENSE.txt).
 */

#include "MTTexture.h"
#include "../MTTypes.h"
#include "../Buffer/MTIntermediateBuffer.h"
#include "../../TextureUtils.h"
#include <LLGL/TextureFlags.h>
#include <LLGL/ImageFlags.h>
#include <LLGL/Utils/ForRange.h>
#include <algorithm>


namespace LLGL
{


static NSUInteger GetTextureLayers(const TextureDescriptor& desc)
{
    if (IsCubeTexture(desc.type))
        return desc.arrayLayers / 6;
    else
        return desc.arrayLayers;
}

static MTLTextureUsage GetTextureUsage(const TextureDescriptor& desc)
{
    MTLTextureUsage usage = 0;

    if ((desc.bindFlags & BindFlags::Sampled) != 0)
        usage |= MTLTextureUsageShaderRead;
    if ((desc.bindFlags & BindFlags::Storage) != 0)
        usage |= MTLTextureUsageShaderWrite;
    if ((desc.bindFlags & (BindFlags::ColorAttachment | BindFlags::DepthStencilAttachment)) != 0)
        usage |= MTLTextureUsageRenderTarget;

    return usage;
}

static MTLResourceOptions GetResourceOptions(const TextureDescriptor& desc)
{
    MTLResourceOptions opt = 0;

    if (IsDepthOrStencilFormat(desc.format))
        opt |= MTLResourceStorageModePrivate;
    #ifndef LLGL_OS_IOS
    else
        opt |= MTLResourceStorageModeManaged;
    #endif // /LLGL_OS_IOS

    return opt;
}

static MTLTextureType ToMTLTextureTypeWithMipMaps(TextureType type)
{
    switch (type)
    {
        case TextureType::Texture1D:        return MTLTextureType2D;
        case TextureType::Texture1DArray:   return MTLTextureType2DArray;
        default:                            return MTTypes::ToMTLTextureType(type);
    }
}

// Returns the most suitable sample count for the Metal device
static NSUInteger FindSuitableSampleCount(id<MTLDevice> device, NSUInteger samples)
{
    while (samples > 1)
    {
        if ([device supportsTextureSampleCount:samples])
            return samples;
        --samples;
    }
    return 4u; // Supported by all macOS and iOS devices; 1 is not supported according to Metal validation layer
}

static void ConvertTextureDesc(id<MTLDevice> device, MTLTextureDescriptor* dst, const TextureDescriptor& src)
{
    /*
    Convert 1D textures to 2D textures of size (Wx1) if MIP-map count is greater than 1
    since Metal does not support MIP-mapped 1D textures.
    */
    const NSUInteger mipMapCount = NumMipLevels(src);

    dst.textureType         = (mipMapCount > 1 ? ToMTLTextureTypeWithMipMaps(src.type) : MTTypes::ToMTLTextureType(src.type));
    dst.pixelFormat         = MTTypes::ToMTLPixelFormat(src.format);
    dst.width               = src.extent.width;
    dst.height              = src.extent.height;
    dst.depth               = src.extent.depth;
    dst.mipmapLevelCount    = mipMapCount;
    dst.sampleCount         = (IsMultiSampleTexture(src.type) ? FindSuitableSampleCount(device, static_cast<NSUInteger>(src.samples)) : 1u);
    dst.arrayLength         = GetTextureLayers(src);
    dst.usage               = GetTextureUsage(src);
    dst.resourceOptions     = GetResourceOptions(src);
    if (IsMultiSampleTexture(src.type) || IsDepthOrStencilFormat(src.format))
        dst.storageMode = MTLStorageModePrivate;
}

MTTexture::MTTexture(id<MTLDevice> device, const TextureDescriptor& desc) :
    Texture { desc.type, desc.bindFlags }
{
    MTLTextureDescriptor* texDesc = [[MTLTextureDescriptor alloc] init];
    ConvertTextureDesc(device, texDesc, desc);
    native_ = [device newTextureWithDescriptor:texDesc];
    [texDesc release];
}

MTTexture::~MTTexture()
{
    [native_ release];
}

Extent3D MTTexture::GetMipExtent(std::uint32_t mipLevel) const
{
    auto w = static_cast<std::uint32_t>([native_ width]);
    auto h = static_cast<std::uint32_t>([native_ height]);
    auto d = static_cast<std::uint32_t>([native_ depth]);
    auto a = static_cast<std::uint32_t>([native_ arrayLength]);

    switch (GetType())
    {
        case TextureType::Texture1D:
        case TextureType::Texture1DArray:
            w = std::max(1u, w >> mipLevel);
            h = a;
            d = 1u;
            break;
        case TextureType::Texture2D:
        case TextureType::Texture2DArray:
            w = std::max(1u, w >> mipLevel);
            h = std::max(1u, h >> mipLevel);
            d = a;
            break;
        case TextureType::Texture3D:
            w = std::max(1u, w >> mipLevel);
            h = std::max(1u, h >> mipLevel);
            d = std::max(1u, d >> mipLevel);
            break;
        case TextureType::TextureCube:
        case TextureType::TextureCubeArray:
            w = std::max(1u, w >> mipLevel);
            h = std::max(1u, h >> mipLevel);
            d = a * 6;
            break;
        case TextureType::Texture2DMS:
        case TextureType::Texture2DMSArray:
            w = std::max(1u, w >> mipLevel);
            h = std::max(1u, h >> mipLevel);
            d = a;
            break;
    }

    return Extent3D{ w, h, d };
}

TextureDescriptor MTTexture::GetDesc() const
{
    TextureDescriptor texDesc;

    texDesc.type            = GetType();
    texDesc.bindFlags       = GetBindFlags();
    texDesc.miscFlags       = 0;
    texDesc.mipLevels       = static_cast<std::uint32_t>([native_ mipmapLevelCount]);
    texDesc.format          = GetFormat();
    texDesc.extent.width    = static_cast<std::uint32_t>([native_ width]);
    texDesc.extent.height   = static_cast<std::uint32_t>([native_ height]);
    texDesc.extent.depth    = static_cast<std::uint32_t>([native_ depth]);
    texDesc.arrayLayers     = static_cast<std::uint32_t>([native_ arrayLength]);
    texDesc.samples         = static_cast<std::uint32_t>([native_ sampleCount]);

    if (IsCubeTexture(GetType()))
        texDesc.arrayLayers *= 6;

    return texDesc;
}

Format MTTexture::GetFormat() const
{
    return MTTypes::ToFormat([native_ pixelFormat]);
}

SubresourceFootprint MTTexture::GetSubresourceFootprint(std::uint32_t mipLevel) const
{
    const auto numArrayLayers = static_cast<std::uint32_t>([native_ arrayLength]);
    return CalcPackedSubresourceFootprint(GetType(), GetFormat(), GetMipExtent(0), mipLevel, numArrayLayers);
}

void MTTexture::WriteRegion(const TextureRegion& textureRegion, const SrcImageDescriptor& imageDesc)
{
    /* Convert region to MTLRegion */
    MTLRegion region;
    MTTypes::Convert(region.origin, textureRegion.offset);
    MTTypes::Convert(region.size, textureRegion.extent);

    /* Get dimensions */
    auto        format          = MTTypes::ToFormat([native_ pixelFormat]);
    const auto& formatAttribs   = GetFormatAttribs(format);
    const auto  layout          = CalcSubresourceLayout(format, textureRegion.extent);
    auto        imageData       = imageDesc.data;

    /* Check if image data must be converted */
    ByteBuffer intermediateData;

    if (formatAttribs.bitSize > 0 && (formatAttribs.flags & FormatFlags::IsCompressed) == 0)
    {
        /* Convert image format (will be null if no conversion is necessary) */
        intermediateData = ConvertImageBuffer(imageDesc, formatAttribs.format, formatAttribs.dataType, /*cfg.threadCount*/0);
        if (intermediateData)
        {
            /* User converted tempoary buffer as image source */
            imageData = intermediateData.get();
        }
    }

    /* Replace region of native texture with source image data */
    auto byteAlignedData = reinterpret_cast<const std::int8_t*>(imageData);

    for_range(arrayLayer, textureRegion.subresource.numArrayLayers)
    {
        [native_
            replaceRegion:  region
            mipmapLevel:    static_cast<NSUInteger>(textureRegion.subresource.baseMipLevel)
            slice:          (textureRegion.subresource.baseArrayLayer + arrayLayer)
            withBytes:      byteAlignedData
            bytesPerRow:    static_cast<NSUInteger>(layout.rowStride)
            bytesPerImage:  static_cast<NSUInteger>(layout.layerStride)
        ];
        byteAlignedData += layout.layerStride;
    }
}

void MTTexture::ReadRegion(
    const TextureRegion&        textureRegion,
    const DstImageDescriptor&   imageDesc,
    id<MTLCommandQueue>         cmdQueue,
    MTIntermediateBuffer*       intermediateBuffer)
{
    /* Convert region to MTLRegion */
    MTLRegion region;
    MTTypes::Convert(region.origin, textureRegion.offset);
    MTTypes::Convert(region.size, textureRegion.extent);

    /* Get dimensions */
    const Format            format          = MTTypes::ToFormat([native_ pixelFormat]);
    const FormatAttributes& formatAttribs   = GetFormatAttribs(format);
    const SubresourceLayout layout          = CalcSubresourceLayout(format, textureRegion.extent);

    if ([native_ storageMode] == MTLStorageModePrivate)
    {
        if (cmdQueue == nil || intermediateBuffer == nullptr)
            return /*Invalid arguments*/;

        ReadRegionFromPrivateMemory(
            region,
            textureRegion.subresource,
            formatAttribs,
            layout,
            imageDesc,
            cmdQueue,
            *intermediateBuffer
        );
    }
    else
    {
        ReadRegionFromSharedMemory(
            region,
            textureRegion.subresource,
            formatAttribs,
            layout,
            imageDesc
        );
    }
}

id<MTLTexture> MTTexture::CreateSubresourceView(const TextureSubresource& subresource)
{
    NSUInteger firstLevel   = static_cast<NSUInteger>(subresource.baseMipLevel);
    NSUInteger numLevels    = static_cast<NSUInteger>(subresource.numMipLevels);
    NSUInteger firstSlice   = static_cast<NSUInteger>(subresource.baseArrayLayer);
    NSUInteger numSlices    = static_cast<NSUInteger>(subresource.numArrayLayers);

    return [native_
        newTextureViewWithPixelFormat:  [native_ pixelFormat]
        textureType:                    [native_ textureType]
        levels:                         NSMakeRange(firstLevel, numLevels)
        slices:                         NSMakeRange(firstSlice, numSlices)
    ];
}

NSUInteger MTTexture::GetBytesPerRow(std::uint32_t rowExtent) const
{
    const Format format = MTTypes::ToFormat([native_ pixelFormat]);
    return LLGL::GetMemoryFootprint(format, rowExtent);
}


/*
 * ======= Private: =======
 */

void MTTexture::ReadRegionFromSharedMemory(
    const MTLRegion&            region,
    const TextureSubresource&   subresource,
    const FormatAttributes&     formatAttribs,
    const SubresourceLayout&    layout,
    const DstImageDescriptor&   imageDesc)
{
    if (formatAttribs.format != imageDesc.format || formatAttribs.dataType != imageDesc.dataType)
    {
        /* Generate intermediate buffer for conversion */
        const std::uint32_t intermediateDataSize    = layout.dataSize * region.size.depth;
        ByteBuffer          intermediateData        = AllocateByteBuffer(intermediateDataSize, UninitializeTag{});

        for_range(arrayLayer, subresource.numArrayLayers)
        {
            /* Copy bytes into intermediate data, then convert its format */
            [native_
                getBytes:       intermediateData.get()
                bytesPerRow:    layout.rowStride
                bytesPerImage:  layout.layerStride
                fromRegion:     region
                mipmapLevel:    subresource.baseMipLevel
                slice:          subresource.baseArrayLayer + arrayLayer
            ];

            /* Convert intermediate data into requested format */
            ByteBuffer formattedData = ConvertImageBuffer(
                SrcImageDescriptor{ formatAttribs.format, formatAttribs.dataType, intermediateData.get(), intermediateDataSize },
                imageDesc.format, imageDesc.dataType, /*GetConfiguration().threadCount*/0
            );

            /* Copy temporary data into output buffer */
            ::memcpy(imageDesc.data, formattedData.get(), imageDesc.dataSize);
        }
    }
    else
    {
        char* dstImageData = reinterpret_cast<char*>(imageDesc.data);

        for_range(arrayLayer, subresource.numArrayLayers)
        {
            /* Copy bytes into intermediate data, then convert its format */
            [native_
                getBytes:       dstImageData
                bytesPerRow:    layout.rowStride
                bytesPerImage:  layout.layerStride
                fromRegion:     region
                mipmapLevel:    subresource.baseMipLevel
                slice:          subresource.baseArrayLayer + arrayLayer
            ];
            dstImageData += layout.layerStride;
        }
    }
}

void MTTexture::ReadRegionFromPrivateMemory(
    const MTLRegion&            region,
    const TextureSubresource&   subresource,
    const FormatAttributes&     formatAttribs,
    const SubresourceLayout&    layout,
    const DstImageDescriptor&   imageDesc,
    id<MTLCommandQueue>         cmdQueue,
    MTIntermediateBuffer&       intermediateBuffer)
{
    /* Copy texture data into intermediate buffer in shared CPU/GPU memory */
    const NSUInteger intermediateDataSize = layout.dataSize * region.size.depth * subresource.numArrayLayers;
    if (imageDesc.dataSize < intermediateDataSize)
        return /*Out of bounds*/;

    intermediateBuffer.Grow(intermediateDataSize);

    id<MTLCommandBuffer> cmdBuffer = [cmdQueue commandBuffer];
    id<MTLBlitCommandEncoder> blitEncoder = [cmdBuffer blitCommandEncoder];

    for_range(arrayLayer, subresource.numArrayLayers)
    {
        /* Copy bytes into intermediate data, then convert its format */
        [blitEncoder
            copyFromTexture:            native_
            sourceSlice:                subresource.baseArrayLayer + arrayLayer
            sourceLevel:                subresource.baseMipLevel
            sourceOrigin:               region.origin
            sourceSize:                 region.size
            toBuffer:                   intermediateBuffer.GetNative()
            destinationOffset:          layout.layerStride * arrayLayer
            destinationBytesPerRow:     layout.rowStride
            destinationBytesPerImage:   layout.layerStride
        ];
    }

    [blitEncoder endEncoding];
    [cmdBuffer commit];
    [cmdBuffer waitUntilCompleted];

    if (formatAttribs.format != imageDesc.format || formatAttribs.dataType != imageDesc.dataType)
    {
        ConvertImageBuffer(
            SrcImageDescriptor{ formatAttribs.format, formatAttribs.dataType, intermediateBuffer.GetBytes(), intermediateDataSize },
            imageDesc
        );
    }
    else
    {
        /* Copy bytes from intermediate shared buffer into output CPU buffer */
        ::memcpy(imageDesc.data, intermediateBuffer.GetBytes(), imageDesc.dataSize);
    }

    [cmdBuffer release];
}


} // /namespace LLGL



// ================================================================================
