import click
import selene_sdk
import selene_sdk.sequences
import numpy
import numpy.random
import sys
import click
import collections
import os
import bx.intervals.intersection
import gzip
import re


@click.command()
@click.option("--genome-file", nargs=1, required=True, type=click.Path(exists=True))
@click.option("--filter-file", nargs=1, required=False, default=None, type=click.Path(exists=True), help="Regions to filter")
@click.option("--sequence-length", nargs=1, required=True, type=click.INT, help="Length of model input sequence")
@click.option("--n-positions", nargs=1, required=True, type=click.INT, help="Number of random snps to make")
@click.option("--max-unk", nargs=1, required=True, type=click.INT, default=50, help="Max unknown bases")
def run(genome_file, filter_file, sequence_length, n_positions, max_unk):
    # Manage inputs.
    buffer_size = 2000000
    numpy.random.seed(1337)
    genome = selene_sdk.sequences.Genome(genome_file)

    # Create dict of filter regions.
    ival_dict = collections.defaultdict(bx.intervals.intersection.IntervalTree)
    with gzip.open(filter_file, "rt") as read_file:
        for line in read_file:
            line = line.strip()
            chrom, start, end = line.split("\t", 3)[:3]
            start = int(start)
            end = int(end)
            ival_dict[chrom].insert(start, end, True)
    known_chroms = set(ival_dict.keys())

    # Setup chromosomes and weighting.
    #x = int(numpy.ceil(sequence_length / 2))
    #xys = [('chr' + x[3:] if x.lower().startswith("chr") else x, y) for (x, y) in genome.get_chr_lens()]
    chr_lens = [(x, y) for x, y in genome.get_chr_lens() if (not x.lower().startswith("chrx")) and
                                            (not x.lower().startswith("chrm")) and
                                            (not x.lower().startswith("chry")) and
                                            (not x.lower().startswith("chru")) and 
                                            (not x.lower().endswith("_random")) and
                                            (not x.lower().endswith("_alt")) and
                                            (x.upper() != "NC_035107.1")] # Mosquito sex chromosome.
    x = sequence_length
    chrom_lens_dict = {k: (x, v - x) for k, v in chr_lens if v > sequence_length and x < (v - x)}
    chrom_lens = list(chrom_lens_dict.items())
    chrom_weights = [(x, z - y) for x, (y, z) in chrom_lens]
    x = sum([x for _, x in chrom_weights])
    chrom_weights = [(k, v / x) for (k, v) in chrom_weights]
    chrom_weights_dict = {k: v for (k, v) in chrom_weights}
    chrom_idxs = list()

    # Setup sets to track what we've already seen.
    seen = set()

    # Generate random samples.
    buffer_i = 0
    for i in range(n_positions):
        while True:
            # We have to reset the buffer.
            if buffer_i >= len(chrom_idxs):
                chrom_idxs = numpy.random.choice(numpy.array([x for x, _ in chrom_weights], dtype=object),
                                                 size=buffer_size, replace=True,
                                                 p=[x for _, x in chrom_weights])
                buffer_i = 0
            # Draw random sample from selected chromosome.
            chrom = chrom_idxs[buffer_i]
            start, end = chrom_lens_dict[chrom]
            pos = numpy.random.randint(start, end)
            buffer_i += 1

            # Filter out anything we've already filtered.
            if (chrom, pos) in seen:
                continue
            else:
                seen.add((chrom, pos))

           # Get region around position.
            start = pos - (sequence_length // 2)
            end = start + sequence_length

            # Check if it is in the interval dict.
            if chrom in ival_dict:
                ret = [x for x in ival_dict[chrom].find(start, end) if x]
                if ret:
                    seen.add((chrom, pos))
                    continue

            # Get sequences.
            seq = genome.get_sequence_from_coords(chrom, start, end, strand="+").upper()

            # Check number of unknown characters.
            n_unk = len(re.sub('[ACTG]', '', seq))
            if n_unk <= max_unk:
                print(chrom, start, end, sep="\t")
                break


if __name__ == "__main__":
    run()

