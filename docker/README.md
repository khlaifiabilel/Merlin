# NVIDIA Merlin Dockerfiles and Containers

All NVIDIA Merlin components are available as open source projects. However, a more convenient way to make use of these components is by using our Merlin NGC containers. We have created Docker containers for NVIDIA Merlin that are hosted on [NGC](https://ngc.nvidia.com/catalog/containers/). 

Containers allow you to package your software application, libraries, dependencies, and runtime compilers in a self-contained environment. These containers can be pulled and launched right out of the box. You can clone and adjust these containers if necessary. 

The table below provides a list of Dockerfiles that can be used to build the corresponding Docker container:

| Container Name             | Dockerfile       | Container Location                                                             | Functionality                                         |
|----------------------------|------------------|--------------------------------------------------------------------------------|-------------------------------------------------------|
| Merlin-training            | dockerfile.ctr   |  https://ngc.nvidia.com/containers/nvidia:merlin:merlin-training            | NVTabular and HugeCTR                                 |
| Merlin-tensorflow-training | dockerfile.tf    |  https://ngc.nvidia.com/containers/nvidia:merlin:merlin-tensorflow-training | NVTabular, TensorFlow, and HugeCTR Tensorflow Embedding plugin |
| Merlin-pytorch-training    | dockerfile.torch |  https://ngc.nvidia.com/containers/nvidia:merlin:merlin-pytorch-training    | NVTabular and PyTorch                                 |
| Merlin-inference           | dockerfile.tri   |  https://ngc.nvidia.com/containers/nvidia:merlin:merlin-inference           | NVTabular, HugeCTR, and Triton Inference               |
