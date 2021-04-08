import sys
import pyfaidx
import tabix
import h5py
import numpy
import os
import click


@click.command()
@click.option("--feature-file", nargs=1, required=True, type=click.Path(exists=True))
@click.option("--interval-file", nargs=1, required=True, type=click.Path(exists=True))
@click.option("--query-file", nargs=1, required=True, type=click.Path(exists=True))
@click.option("--output-file", nargs=1, required=True, type=click.Path(exists=False))
def run(feature_file, interval_file, query_file, output_file):
    # Read in features.
    features = list()
    feat_to_idx_dict = dict()
    with open(feature_file, "r") as read_file:
        for line in read_file:
            line = line.strip()
            if line != "":
                features.append(line)
                feat_to_idx_dict[line] = len(features) - 1

    # Create tabix for labels.
    cur_tabix = tabix.open(interval_file)

    # Check rows.
    with open(query_file, "r") as read_file:
        n_rows = 0
        for line in enumerate(read_file):
            n_rows += 1

    # Read in queries.
    h5 = h5py.File(output_file, "w")
    out_data = h5.create_dataset("data", (n_rows, len(features)))
    with open(query_file, "r") as read_file:
        for i, line in enumerate(read_file):
            chrom, start, end = line.rstrip().split("\t", 3)[:3]
            start = int(start)
            end = int(end)
            start, end = min(start, end), max(start, end)
            start = start + 2047
            end = start + 1
            try:
                for _, s, e, f in cur_tabix.query(chrom, start, end):
                    out_data[i, feat_to_idx_dict[f]] = 1.
            except:
                print("Chrom {} not found in tabix".format(chrom), flush=True)
    h5.close()


if __name__ == "__main__":
    run()

