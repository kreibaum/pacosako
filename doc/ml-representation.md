# Machine Learning Representation for Paco Ŝako

This document describes the machine learning (ML) representation
we are using for Paco Ŝako. 

## Options

To allow us to explore different representations while keeping backwards
compatibility with old existing models, we pass in options when building
the representation.

## Index Representation

The index representation (idx_repr) is a compact format that can be
efficiently transfered to the GPU.

## Tensor Representation

An Alpha-Zero style model can't operate directly on a dense index representation.
The index representation is always expanded to a tensor representation. This
either happens directly in the model, or before applying the model.
It is prefered to apply the model to the index representation directly,
but not all inference frameworks support the required operators.