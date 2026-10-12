# A graph that learns handwritten digits

This model example separates building a tensor computation from executing it.
A training node loads compiled artifacts, owns device buffers, and exchanges
progress messages with a browser workbook.

## Build the computation

An ordinary `build.scm` calls the application's chosen tensor compiler libraries.
Those libraries capture a graph, check types and shapes, differentiate it, and
generate CPU or GPU code. The script publishes that code alongside the training
and browser artifacts.

A shader declaration is compiler input; it need not be a callable Scheme
procedure. Compiler calls are ordinary local library calls. They need no node
boundary, and compiling a graph performs no training.

## Run the computation

A runtime starts the training node with the graph artifacts and dataset
configuration. The training node initializes its parameters and device buffers,
then runs training steps. A browser workbook connects to it to request pause,
resume, checkpoint, or cancellation and receive progress messages.

The runtimes handle connection setup, encoding, communication, and errors.
Parameters stay with the training node. Progress messages contain values such
as the step, loss, and accuracy; their size need not grow with the weight buffers.
The training node retains buffers until dispatched device work completes.

## Define the workflow/session

The application decides whether closing the browser merely hangs up or also
asks the lifetime owner to stop training. A disconnected workbook can reconnect
to the same running node and request its current progress.

A resumable checkpoint includes parameters, optimizer state, random-number
state, and dataset position. Replacing a computation artifact requires checking
compatibility with that state. In-flight work keeps the resources and artifact
version it started with.

Pure reference calculations, actual device execution, and complete training
establish different facts. A graph compiling successfully does not establish
correct derivatives or device behavior. The model supplies ownership and
communication rules; the tensor libraries and runtime supply the computation.
