# from single_sentence_time_aligner import EMPTY_STRING, UNKNOWN
import single_sentence_time_aligner
from Levenshtein import distance
import argparse
import yaml
import shared
import os
import numpy as np

parser = argparse.ArgumentParser()
# 2013/11/27/2013112710081022.mp3
parser.add_argument("--vertical",
                    default='/home/stankvla/Projects/Python/Comp-in-MT/align/verticals-sample/merged/2013112710081022.vert',
                    type=str,
                    help="If true is passed then all computed time alignment will be rewritten.")

parser.add_argument("--transcript",
                    default='/home/stankvla/Projects/Python/Comp-in-MT/align/verticals-sample/time-extracted/jan/2013112710081022.tsv',
                    type=str,
                    help="Number of jobs that will run parallel.")

parser.add_argument("--yaml_config",
                    # default='/home/stankvla/Projects/Python/Comp-in-MT/align/lindat',
                    default='/home/stankvla/Projects/Python/Comp-in-MT/align/working_dir/configs/config.yaml',
                    type=str,
                    help="Directory with source mp3 files.")

parser.add_argument("--output",
                    # default='/home/stankvla/Projects/Python/Comp-in-MT/align/lindat',
                    default='example_output/output.txt',
                    type=str,
                    help="Output file name (full path).")

# %%
if __name__ == '__main__':
    # %%
    args = parser.parse_args([] if "__file__" not in globals() else None)
    if '.tsv' not in args.output:
        args.output += '.tsv'

    with open(args.yaml_config, 'r') as file:
        # The FullLoader parameter handles the conversion from YAML
        # scalar values to Python the dictionary format
        config = yaml.load(file, Loader=yaml.FullLoader)

    start_penalty = config['start_penalty']
    extend_penalty = config['extend_penalty']
    vert_inst = single_sentence_time_aligner.VerticalFile(args.vertical)
    trans_inst = single_sentence_time_aligner.TranscriptionFile(args.transcript)

    aligner = single_sentence_time_aligner.Aligner(start_penalty=start_penalty, extend_penalty=extend_penalty)
    # here we are passing text from transcription and vertical and get indices to this text
    # further we will operate on indices
    _, _, vert_indices, trans_indices, some_score = aligner.align(trans_inst.get_normalized(), vert_inst.get_normalized())
    single_sentence_time_aligner.display_alignment(vert_indices, trans_indices, vert_inst, trans_inst)
    # %%
    vert_indices_updated, trans_indices_updated, windows_cnt = single_sentence_time_aligner.solve_window_alignment(trans_indices, vert_indices, trans_inst, vert_inst)
    zipped = list(zip(vert_indices_updated, trans_indices_updated))
    # %%
    header = ['true_w', 'trans_w', 'joined', 'id', 'recognized', 'dist', 'dist/len(true_word)', 'start', 'end', 'time_len_ms', 'time_len/len(true_word)']
    output = []
    maxes = [len(s) for s in header]
    word_alignment = [header]

    with open(args.output.replace('.tsv', '.stats'), 'w') as f:
        missed_percentage, normalized_edit_distances, normalized_edit_distances_with_gaps = single_sentence_time_aligner.score_alignment(vert_indices_updated, trans_indices_updated, vert_inst, trans_inst)
        head = ['missed_percentage', 'median_normalized_dist', 'normalized_dist_75', 'normalized_dist_90', 'median_normalized_dist_including_gaps', 'normalized_dist_with_gaps_75', 'normalized_dist_with_gaps_90']
        stats = [
            missed_percentage,
            np.median(normalized_edit_distances),
            np.percentile(normalized_edit_distances, 75),
            np.percentile(normalized_edit_distances, 90),

            np.median(normalized_edit_distances_with_gaps),
            np.percentile(normalized_edit_distances_with_gaps, 75),
            np.percentile(normalized_edit_distances_with_gaps, 90),
        ]
        stats = [f'{x:>.3f}' for x in stats]
        print('\t'.join(head), file=f)
        print('\t'.join(stats), file=f)

    for i, (i1, i2) in enumerate(zipped):
        norm_vert_word = vert_inst.get_normalized_range_flat(i1)
        norm_trans_word = trans_inst.get_normalized_range_flat(i2)
        vert_word = vert_inst.get_text_range_flat(i1)
        trans_word = trans_inst.get_text_range_flat(i2)


        alignment_dict = {h: shared.UNKNOWN for h in header}
        alignment_dict['recognized'] = 'False'
        alignment_dict['joined'] = 'False'

        alignment_dict['true_w'] = vert_word
        alignment_dict['trans_w'] = trans_word

        if shared.UNKNOWN not in trans_word:
            start_time, end_time = trans_inst.get_starts_ends_range(i2)
            start_time = 1000 * start_time
            end_time = 1000 * end_time
            time_len = end_time - start_time
            alignment_dict['start'] = f"{start_time:.1f}"
            alignment_dict['end'] = f"{end_time:.1f}"
            alignment_dict['time_len_ms'] = f"{time_len:.1f}"

        if shared.UNKNOWN not in vert_word:
            alignment_dict['id'] = vert_inst.get_id_by_index(i1)

        if shared.UNKNOWN not in trans_word and shared.UNKNOWN not in vert_word:
            dist = distance(norm_vert_word, norm_trans_word)
            if isinstance(i2, list) and len(i2) > 1:
                alignment_dict['joined'] = f"{len(i2) > 1}"
            alignment_dict['recognized'] = 'True'
            alignment_dict['dist'] = f'{dist}'
            alignment_dict['dist/len(true_word)'] = f"{dist / len(alignment_dict['true_w']):.3f}"
            alignment_dict['time_len/len(true_word)'] = f"{time_len / len(alignment_dict['true_w']):.3f}"

        output.append(alignment_dict)

    with open(args.output, 'w') as f:
        f.write('\t'.join(header) + '\n')
        for r in output:
            f.write('\t'.join([r[key] for key in header]) + '\n')
            # f.write('\t'.join([f"{r[key]:25}" for key in header]) + '\n')

    # with open(args.output.replace('words', 'stats'), 'w') as f:
    #     missed_percentage, median_norm_dist, median_norm_dist_with_gaps = single_sentence_time_aligner.score_alignment(vert_indices, trans_indices, vert_inst, trans_inst)
    #     head = ['missed_percentage', 'median_normalized_dist', 'median_normalized_dist_including_gaps', 'windows_solved']
    #     stats = [missed_percentage, median_norm_dist, median_norm_dist_with_gaps, windows_cnt/max(vert_indices)]
    #     stats = [f'{x:>.3f}' for x in stats]
    #     print('\t'.join(head), file=f)
    #     print('\t'.join(stats), file=f)


