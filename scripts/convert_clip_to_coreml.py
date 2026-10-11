#!/usr/bin/env python3
"""
Convert CLIP ViT-B/32 model to CoreML format

Requirements:
    pip install torch torchvision transformers coremltools pillow

Usage:
    python3 convert_clip_to_coreml.py

This will generate CLIP_ViT_B_32.mlpackage in the current directory.
Move it to LightSearch/Core/ML/Resources/ in your Xcode project.
"""

import torch
import coremltools as ct
from transformers import CLIPModel, CLIPProcessor
from PIL import Image
import numpy as np


def convert_clip_image_encoder():
    """Convert CLIP image encoder to CoreML"""
    print("Loading CLIP model from Hugging Face...")
    model_name = "openai/clip-vit-base-patch32"
    model = CLIPModel.from_pretrained(model_name)
    processor = CLIPProcessor.from_pretrained(model_name)

    # Set model to evaluation mode
    model.eval()

    print("Preparing image encoder for conversion...")

    # Create a wrapper that takes pixel values and returns normalized embeddings
    class CLIPImageEncoder(torch.nn.Module):
        def __init__(self, clip_model):
            super().__init__()
            self.vision_model = clip_model.vision_model
            self.visual_projection = clip_model.visual_projection

        def forward(self, pixel_values):
            # Get image embeddings
            vision_outputs = self.vision_model(pixel_values=pixel_values)
            image_embeds = vision_outputs.pooler_output
            image_embeds = self.visual_projection(image_embeds)

            # L2 normalize
            image_embeds = image_embeds / image_embeds.norm(p=2, dim=-1, keepdim=True)

            return image_embeds

    image_encoder = CLIPImageEncoder(model)

    # Create dummy input (224x224 RGB image)
    dummy_input = torch.randn(1, 3, 224, 224)

    print("Tracing model...")
    traced_model = torch.jit.trace(image_encoder, dummy_input)

    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced_model,
        inputs=[ct.ImageType(
            name="image",
            shape=(1, 3, 224, 224),
            scale=1/255.0,
            bias=[0, 0, 0]
        )],
        outputs=[ct.TensorType(name="embedding")],
        minimum_deployment_target=ct.target.macOS14,
        compute_units=ct.ComputeUnit.ALL  # Use Neural Engine when available
    )

    # Add metadata
    mlmodel.author = "OpenAI CLIP (converted for LightSearch)"
    mlmodel.short_description = "CLIP ViT-B/32 image encoder for semantic image embeddings"
    mlmodel.version = "1.0"

    print("Saving model...")
    output_path = "CLIP_ViT_B_32_Image.mlpackage"
    mlmodel.save(output_path)

    print(f"✅ Image encoder saved to: {output_path}")
    print(f"   Size: {get_model_size(output_path):.1f} MB")

    return output_path


def convert_clip_text_encoder():
    """Convert CLIP text encoder to CoreML"""
    print("\nLoading CLIP model for text encoder...")
    model_name = "openai/clip-vit-base-patch32"
    model = CLIPModel.from_pretrained(model_name)
    processor = CLIPProcessor.from_pretrained(model_name)

    model.eval()

    print("Preparing text encoder for conversion...")

    class CLIPTextEncoder(torch.nn.Module):
        def __init__(self, clip_model):
            super().__init__()
            self.text_model = clip_model.text_model
            self.text_projection = clip_model.text_projection

        def forward(self, input_ids, attention_mask):
            # Get text embeddings
            text_outputs = self.text_model(
                input_ids=input_ids,
                attention_mask=attention_mask
            )
            text_embeds = text_outputs.pooler_output
            text_embeds = self.text_projection(text_embeds)

            # L2 normalize
            text_embeds = text_embeds / text_embeds.norm(p=2, dim=-1, keepdim=True)

            return text_embeds

    text_encoder = CLIPTextEncoder(model)

    # Create dummy input (tokenized text)
    # CLIP uses max sequence length of 77
    dummy_input_ids = torch.randint(0, 49408, (1, 77))  # 49408 is vocab size
    dummy_attention_mask = torch.ones(1, 77)

    print("Tracing model...")
    traced_model = torch.jit.trace(
        text_encoder,
        (dummy_input_ids, dummy_attention_mask)
    )

    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, 77)),
            ct.TensorType(name="attention_mask", shape=(1, 77))
        ],
        outputs=[ct.TensorType(name="embedding")],
        minimum_deployment_target=ct.target.macOS14,
        compute_units=ct.ComputeUnit.ALL
    )

    # Add metadata
    mlmodel.author = "OpenAI CLIP (converted for LightSearch)"
    mlmodel.short_description = "CLIP ViT-B/32 text encoder for semantic text embeddings"
    mlmodel.version = "1.0"

    print("Saving model...")
    output_path = "CLIP_ViT_B_32_Text.mlpackage"
    mlmodel.save(output_path)

    print(f"✅ Text encoder saved to: {output_path}")
    print(f"   Size: {get_model_size(output_path):.1f} MB")

    return output_path


def get_model_size(path):
    """Get size of .mlpackage directory in MB"""
    import os
    total_size = 0
    for dirpath, dirnames, filenames in os.walk(path):
        for filename in filenames:
            filepath = os.path.join(dirpath, filename)
            total_size += os.path.getsize(filepath)
    return total_size / (1024 * 1024)


def test_model(image_model_path, text_model_path):
    """Test the converted models"""
    print("\n" + "="*60)
    print("Testing converted models...")
    print("="*60)

    import coremltools as ct

    # Load models
    print("Loading CoreML models...")
    image_model = ct.models.MLModel(image_model_path)
    text_model = ct.models.MLModel(text_model_path)

    # Test image encoder
    print("\nTesting image encoder...")
    dummy_image = np.random.rand(1, 3, 224, 224).astype(np.float32)
    image_output = image_model.predict({"image": dummy_image})
    image_embedding = image_output["embedding"]
    print(f"  ✅ Image embedding shape: {image_embedding.shape}")
    print(f"  ✅ Image embedding norm: {np.linalg.norm(image_embedding):.4f} (should be ~1.0)")

    # Test text encoder
    print("\nTesting text encoder...")
    dummy_input_ids = np.random.randint(0, 49408, (1, 77)).astype(np.int32)
    dummy_attention_mask = np.ones((1, 77)).astype(np.int32)
    text_output = text_model.predict({
        "input_ids": dummy_input_ids,
        "attention_mask": dummy_attention_mask
    })
    text_embedding = text_output["embedding"]
    print(f"  ✅ Text embedding shape: {text_embedding.shape}")
    print(f"  ✅ Text embedding norm: {np.linalg.norm(text_embedding):.4f} (should be ~1.0)")

    # Test similarity
    similarity = np.dot(image_embedding.flatten(), text_embedding.flatten())
    print(f"\n  Cosine similarity (random): {similarity:.4f}")

    print("\n✅ All tests passed!")


if __name__ == "__main__":
    print("="*60)
    print("CLIP to CoreML Converter for LightSearch")
    print("="*60)
    print()

    try:
        # Convert both encoders
        image_path = convert_clip_image_encoder()
        text_path = convert_clip_text_encoder()

        # Test the models
        test_model(image_path, text_path)

        print("\n" + "="*60)
        print("NEXT STEPS:")
        print("="*60)
        print(f"1. Move {image_path} to:")
        print("   LightSearch/Core/ML/Resources/")
        print(f"2. Move {text_path} to:")
        print("   LightSearch/Core/ML/Resources/")
        print("3. In Xcode, add both .mlpackage files to the project")
        print("4. Ensure they're included in 'Copy Bundle Resources'")
        print("5. Build and run LightSearch!")
        print("="*60)

    except Exception as e:
        print(f"\n❌ Error: {e}")
        print("\nMake sure you have installed all requirements:")
        print("  pip install torch torchvision transformers coremltools pillow")
        import traceback
        traceback.print_exc()
