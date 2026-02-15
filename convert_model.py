#!/usr/bin/env python3
"""
Convert the all-MiniLM-L6-v2 model from HuggingFace to Core ML format.

Requirements:
    pip install coremltools transformers torch

Usage:
    python convert_model.py

Outputs:
    - MiniLM.mlmodelc/   (compiled Core ML model — add to Xcode as bundle resource)
    - vocab.txt           (WordPiece vocabulary — add to Xcode as bundle resource)

The script downloads the model from HuggingFace, exports it via torch.export,
and converts to Core ML with float32 precision. The resulting model accepts
input_ids and attention_mask of shape [1, 128] and outputs a 384-dim
sentence embedding.
"""

import os
import shutil

import coremltools as ct
import numpy as np
import torch
from torch.export import export
from transformers import AutoModel, AutoTokenizer


MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
MAX_SEQ_LENGTH = 128
OUTPUT_MODEL_NAME = "MiniLM"


def mean_pooling(model_output, attention_mask):
    """Mean pooling — take the average of all token embeddings, weighted by attention mask."""
    token_embeddings = model_output.last_hidden_state
    input_mask_expanded = attention_mask.unsqueeze(-1).expand(token_embeddings.size()).float()
    return torch.sum(token_embeddings * input_mask_expanded, 1) / torch.clamp(
        input_mask_expanded.sum(1), min=1e-9
    )


class WrappedModel(torch.nn.Module):
    """Wraps the transformer to output a single pooled + normalized embedding."""

    def __init__(self, transformer, max_seq_length):
        super().__init__()
        self.transformer = transformer
        # Pre-register position_ids so they become a constant in the trace,
        # avoiding a dynamic int cast that coremltools cannot convert.
        self.register_buffer(
            "position_ids", torch.arange(max_seq_length).unsqueeze(0)
        )

    def forward(self, input_ids, attention_mask):
        outputs = self.transformer(
            input_ids=input_ids,
            attention_mask=attention_mask,
            position_ids=self.position_ids,
        )
        pooled = mean_pooling(outputs, attention_mask)
        normalized = torch.nn.functional.normalize(pooled, p=2, dim=1)
        return normalized


def main():
    print(f"Loading model: {MODEL_NAME}")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    transformer = AutoModel.from_pretrained(MODEL_NAME)
    transformer.eval()

    model = WrappedModel(transformer, MAX_SEQ_LENGTH)
    model.eval()

    # Export vocab.txt
    vocab_path = "vocab.txt"
    vocab = tokenizer.get_vocab()
    sorted_vocab = sorted(vocab.items(), key=lambda x: x[1])
    with open(vocab_path, "w", encoding="utf-8") as f:
        for token, _ in sorted_vocab:
            f.write(f"{token}\n")
    print(f"Exported vocabulary ({len(sorted_vocab)} tokens) to {vocab_path}")

    # Create dummy inputs
    dummy_input_ids = torch.zeros(1, MAX_SEQ_LENGTH, dtype=torch.int32)
    dummy_attention_mask = torch.ones(1, MAX_SEQ_LENGTH, dtype=torch.int32)

    # Export via torch.export (avoids torch.jit.trace int-cast ops that coremltools cannot convert)
    print("Exporting model with torch.export...")
    exported_model = export(model, (dummy_input_ids, dummy_attention_mask))
    exported_model = exported_model.run_decompositions({})

    # Convert to Core ML
    print("Converting to Core ML...")
    mlmodel = ct.convert(
        exported_model,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, MAX_SEQ_LENGTH), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, MAX_SEQ_LENGTH), dtype=np.int32),
        ],
        outputs=[
            ct.TensorType(name="embeddings"),
        ],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
    )

    # Save .mlpackage
    mlpackage_path = f"{OUTPUT_MODEL_NAME}.mlpackage"
    mlmodel.save(mlpackage_path)
    print(f"Saved Core ML model to {mlpackage_path}")

    # Compile to .mlmodelc using coremltools
    print("Compiling to .mlmodelc ...")
    compiled_path = f"{OUTPUT_MODEL_NAME}.mlmodelc"
    if os.path.exists(compiled_path):
        shutil.rmtree(compiled_path)

    # Use xcrun to compile the model (macOS only)
    exit_code = os.system(f"xcrun coremlcompiler compile {mlpackage_path} .")
    if exit_code == 0 and os.path.exists(compiled_path):
        print(f"Compiled model saved to {compiled_path}")
    else:
        print(
            f"Auto-compilation skipped (exit code {exit_code}). "
            f"Open {mlpackage_path} in Xcode to compile, or run:\n"
            f"  xcrun coremlcompiler compile {mlpackage_path} ."
        )

    print("\nDone! Add these to your Xcode project as bundle resources:")
    print(f"  - {compiled_path if os.path.exists(compiled_path) else mlpackage_path}")
    print(f"  - {vocab_path}")


if __name__ == "__main__":
    main()
