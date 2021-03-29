"""
Description:
    This script builds the model and trains it using user-specified input data.

Output:
    Saves model to a user-specified output file.

Usage:
    selene_cli.py <config-yml> [--lr=<lr>]
    selene_cli.py -h | --help

Options:
    -h --help               Show this screen.

    <config-yml>            Model-specific parameters
    --lr=<lr>               If training, the optimizer's learning rate
                            [default: None]
"""
from docopt import docopt
import torch
import torch.multiprocessing

from selene_sdk.utils import parse_configs_and_run
from selene_sdk import __version__


if __name__ == "__main__":
    arguments = docopt(
        __doc__,
        version=__version__)

    torch.multiprocessing.set_start_method("spawn", force=True)
    if arguments["--lr"]:
        print("lr: {0}".format(arguments["--lr"]))
    print(arguments)
    parse_configs_and_run(arguments["<config-yml>"], lr=arguments["--lr"])
