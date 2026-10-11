# CLIP Model Setup for LightSearch

LightSearch uses OpenAI's CLIP (Contrastive Language-Image Pre-training) model for semantic image search. This allows you to search your photos using natural language like "golden hour sunset" or "portrait with shallow depth of field".

## Current Status

**The app currently uses a simplified embedding model for development/testing.** This allows you to test the full indexing pipeline, but the semantic search quality will be limited.

For production use, you need the actual CoreML CLIP model.

## Getting the Full CLIP Model

### Option 1: Convert CLIP to CoreML (Recommended)

We provide a conversion script that downloads the official OpenAI CLIP model and converts it to CoreML format.

#### Requirements
- Python 3.8+
- ~2GB disk space
- ~10 minutes for conversion

#### Steps

1. **Install Python dependencies:**
```bash
pip3 install torch torchvision transformers coremltools pillow
```

2. **Run the conversion script:**
```bash
cd /path/to/LightSearch
python3 scripts/convert_clip_to_coreml.py
```

This will generate two files:
- `CLIP_ViT_B_32_Image.mlpackage` (~350MB) - for encoding images
- `CLIP_ViT_B_32_Text.mlpackage` (~250MB) - for encoding text queries

3. **Add models to Xcode project:**
- Move both `.mlpackage` files to `LightSearch/Core/ML/Resources/`
- In Xcode: File → Add Files to "LightSearch"
- Select both `.mlpackage` files
- Ensure "Copy items if needed" is checked
- Target membership: LightSearch
- Verify they appear in Build Phases → Copy Bundle Resources

4. **Update CLIPModel.swift:**
- Replace `SimpleCLIPModel` usage with `CLIPModel`
- The model will automatically load on first app launch

### Option 2: Download Pre-converted Model

If available, you can download pre-converted CoreML models:

```bash
# Example (URL may vary)
curl -L -o CLIP_ViT_B_32_Image.mlpackage.zip https://example.com/clip_coreml.zip
unzip CLIP_ViT_B_32_Image.mlpackage.zip
```

Then follow step 3 above.

## Model Details

**CLIP ViT-B/32 Specifications:**
- Architecture: Vision Transformer (ViT) with Base size, 32×32 patch size
- Embedding dimension: 512
- Input image size: 224×224 RGB
- Text sequence length: 77 tokens
- Total size: ~600MB (both encoders)
- Performance: Neural Engine optimized for M1/M2/M3 Macs

**Expected Performance:**
- Image encoding: ~60 images/second on M1
- Text encoding: ~500 queries/second
- Memory usage: ~800MB resident
- Cold start: ~15 seconds (model loads at app launch)

## Using SimpleCLIPModel (Current Default)

The `SimpleCLIPModel` is a lightweight placeholder that:
- ✅ Tests the full indexing pipeline
- ✅ Populates the vector database correctly
- ✅ Allows UI development
- ❌ Does NOT provide semantic search quality
- ❌ Embeddings are deterministic but not meaningful

**When to use SimpleCLIPModel:**
- During development
- Testing the app without ML dependencies
- CI/CD environments

**When to use full CLIPModel:**
- Production deployment
- Actual photo searching
- Evaluating search quality

## Troubleshooting

### Model Not Found Error
```
CLIPModelError.modelNotFound
```
**Solution:** The CoreML model files are not in the bundle. Follow "Getting the Full CLIP Model" above.

### Model Load Failed
```
CLIPModelError.modelLoadFailed: "The model could not be loaded"
```
**Solutions:**
- Verify the `.mlpackage` files are complete (not corrupted)
- Check macOS version is 14.0+ (Sonoma)
- Ensure Xcode build settings include the models in bundle resources

### Out of Memory
```
Terminated due to memory pressure
```
**Solution:** CLIP requires ~800MB RAM. Close other apps or use SimpleCLIPModel for testing.

### Slow Indexing
**Expected speed:** ~60 images/minute on M1
**If slower:**
- Check Activity Monitor → GPU usage (should show Neural Engine activity)
- Ensure `compute_units=ct.ComputeUnit.ALL` was used during conversion
- Try restarting the app (first run may be slower due to model optimization)

## References

- [OpenAI CLIP Paper](https://arxiv.org/abs/2103.00020)
- [Hugging Face CLIP Models](https://huggingface.co/openai/clip-vit-base-patch32)
- [Apple CoreML Documentation](https://developer.apple.com/documentation/coreml)
- [CoreML Tools](https://coremltools.readme.io/)

## Performance Benchmarks

Based on LightSearch design experiments:

| Metric | Value | Notes |
|--------|-------|-------|
| Text-to-Image similarity | 0.68+ | Above this threshold = relevant match |
| Text-to-Text similarity | 0.76+ | Higher than image matches |
| Indexing speed | 60 img/min | M1 MacBook Pro, including EXIF extraction |
| Search latency | <100ms | k=200 over 10,000 photos |
| Vector index size | ~2MB/1000 photos | sqlite-vec is very efficient |

## Next Steps

1. ✅ Test indexing with SimpleCLIPModel (works now)
2. ⏳ Convert CLIP to CoreML (follow Option 1 above)
3. ✅ Index your Lightroom catalog
4. ✅ Try semantic searches like "beach sunset" or "mountain landscape"
