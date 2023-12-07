# %%
from Levenshtein import distance
import numpy as np
from unidecode import unidecode
from num2words import num2words
from abc import ABC
import argparse
import yaml
import shared
import logging
import pydub
import os
import sys
import json

parser = argparse.ArgumentParser()

parser.add_argument("--vertical",
                    default='/home/stankvla/Projects/Python/Comp-in-MT/align/new-verticals-sample/merged/2013112720482102.vert',
                    type=str,
                    help="If true is passed then all computed time alignment will be rewritten.")

parser.add_argument("--transcript",
                    default='/home/stankvla/Projects/Python/Comp-in-MT/align/new-verticals-sample/time-extracted/jan/2013112720482102.tsv',
                    type=str,
                    help="Number of jobs that will run parallel.")

parser.add_argument("--mp3",
                    default='/home/stankvla/Projects/Python/Comp-in-MT/align/lindat/2013ps/audio/2013/11/25/2013112720482102.mp3',
                    type=str,
                    help="Number of jobs that will run parallel.")

parser.add_argument("--yaml_config",
                    # default='/home/stankvla/Projects/Python/Comp-in-MT/align/lindat',
                    default='/home/stankvla/Projects/Python/Comp-in-MT/align/working_dir/configs/experiments/config_-5_-1_1.yaml',
                    type=str,
                    help="Path to yaml config file, that stores params for the algorithm.")

parser.add_argument("--output_dir",
                    # default='/home/stankvla/Projects/Python/Comp-in-MT/align/lindat',
                    default='example_output/',
                    type=str,
                    help="Output file name (full path).")


class Sentence:
    def __init__(self):
        self.vert_indices = []
        # indices in the transcription
        self.trans_indices = []
        self.start = -1
        self.end = 0

    def __repr__(self):
        return f'{self.vert_indices}\n{self.trans_indices}\nstart={self.start},end={self.end}'

    def __str__(self):
        return f'{self.vert_indices}\n{self.trans_indices}\nstart={self.start},end={self.end}'


class Aligner:
    def __init__(self, start_penalty=-5, extend_penalty=-5, mult=3):
        self.minimum = - float('inf')
        self.start_penalty = start_penalty
        self.extend_penalty = extend_penalty
        self.mult = mult

    def _match(self, trans, vert, v_i, t_i):
        # if match the len of the string is return
        # otherwise return len of the longest string - 2 * edit distance
        # multiple of edit distance is used to have stronger penalty for mismatches
        return len(vert[v_i - 1]) - self.mult * distance(vert[v_i - 1], trans[t_i - 1])

    @staticmethod
    def _init_empty_matrix(dim_i, dim_j, is_list=False):
        return [[list() if is_list else 0 for _ in range(dim_j)] for _ in range(dim_i)]

    def _init_element(self, k, cond1, cond2):
        if cond1:
            return self.minimum
        if cond2:
            return self.start_penalty + (self.extend_penalty * k)
        return 0

    # initializers for matrices
    def _init_Y(self, dim_i, dim_j):
        YY = self._init_empty_matrix(dim_i, dim_j)
        pYY = self._init_empty_matrix(dim_i, dim_j, is_list=True)

        for i in range(dim_i):
            for j in range(dim_j):
                if j == 0 or i == 0:
                    YY[i][j] = self._init_element(j, i > 0 and j == 0, j > 0)
                if i == 0 and j > 0:
                    pYY[i][j] = ['Y', (i, j - 1)]
        return YY, pYY

    def _init_X(self, dim_i, dim_j):
        XX = self._init_empty_matrix(dim_i, dim_j)
        pXX = self._init_empty_matrix(dim_i, dim_j, is_list=True)
        for i in range(0, dim_i):
            for j in range(0, dim_j):
                if j == 0 or i == 0:
                    XX[i][j] = self._init_element(i, j > 0 and i == 0, i > 0)
                if j == 0 and i > 0:
                    pXX[i][j] = ['X', (i - 1, j)]
        return XX, pXX

    def _init_m(self, i, j):
        if j == 0 and i == 0:
            return 0
        if j == 0 or i == 0:
            return self.minimum
        return 0

    def _distance_matrix(self, trans, vert):
        trans = [unidecode(x).lower() for x in trans]
        vert = [unidecode(x).lower() for x in vert]
        dim_trans = len(trans) + 1
        dim_vert = len(vert) + 1
        # matrices with prefix "p" are pointer matrices that will be used during back tracing
        YY, pYY = self._init_Y(dim_vert, dim_trans)
        XX, pXX = self._init_X(dim_vert, dim_trans)
        M = [[self._init_m(v_i, t_i) for t_i in range(0, dim_trans)] for v_i in range(0, dim_vert)]
        pM = self._init_empty_matrix(dim_vert, dim_trans, is_list=True)
        for t_i in range(1, dim_trans):
            pM[0][t_i] = ['Y', [0, t_i]]
        for v_i in range(1, dim_vert):
            pM[v_i][0] = ['X', [v_i, 0]]

        for t_i in range(1, dim_trans):
            for v_i in range(1, dim_vert):
                yy = [self.start_penalty + M[v_i][t_i - 1], self.extend_penalty + YY[v_i][t_i - 1]]
                xx = [self.start_penalty + M[v_i - 1][t_i], self.extend_penalty + XX[v_i - 1][t_i]]

                YY[v_i][t_i] = max(yy)
                XX[v_i][t_i] = max(xx)

                m = np.array([
                    M[v_i - 1][t_i - 1],
                    YY[v_i - 1][t_i - 1],
                    XX[v_i - 1][t_i - 1]
                ]) + self._match(trans, vert, v_i, t_i)

                M[v_i][t_i] = max(m)
                # fill pointer matrices
                pYY[v_i][t_i] = ['M', (v_i, t_i - 1)] if np.argmax(yy) == 0 else ['Y', (v_i, t_i - 1)]
                pXX[v_i][t_i] = ['M', (v_i - 1, t_i)] if np.argmax(xx) == 0 else ['X', (v_i - 1, t_i)]
                tmp = np.argmax(m)
                if tmp == 0:
                    pM[v_i][t_i] = ['M', (v_i - 1, t_i - 1)]
                elif tmp == 1:
                    pM[v_i][t_i] = ['Y', (v_i - 1, t_i - 1)]
                else:
                    pM[v_i][t_i] = ['X', (v_i - 1, t_i - 1)]
        return [YY, XX, M, pYY, pXX, pM]

    def align(self, trans, vert):
        seq1, seq2, indices1, indices2 = [], [], [], []
        dim_j = len(trans)
        dim_i = len(vert)
        YY, XX, M, pYY, pXX, pM = self._distance_matrix(trans, vert)
        # find where to start and also initialize variables
        k = np.argmax([M[dim_i][dim_j], XX[dim_i][dim_j], YY[dim_i][dim_j]])
        score = max([M[dim_i][dim_j], XX[dim_i][dim_j], YY[dim_i][dim_j]])
        if k == 0:
            current_matrix = 'M'
            current_pointer_matrix = pM
        elif k == 1:
            current_pointer_matrix = pXX
            current_matrix = 'X'
        else:
            current_pointer_matrix = pYY
            current_matrix = 'Y'

        i, j = dim_i, dim_j
        while True:
            if current_matrix == 'M':
                seq1.append(vert[i - 1])
                indices1.append(i - 1)
                seq2.append(trans[j - 1])
                indices2.append(j - 1)
            elif current_matrix == 'X':
                seq1.append(vert[i - 1])
                indices1.append(i - 1)
                seq2.append(shared.EMPTY_STRING * len(vert[i - 1]))
                indices2.append(-1)
            else:
                seq1.append(shared.EMPTY_STRING * len(trans[j - 1]))
                indices1.append(-1)
                seq2.append(trans[j - 1])
                indices2.append(j - 1)

            next_matrix, (i, j) = current_pointer_matrix[i][j]

            if i == 0 and j == 0:
                break

            if current_pointer_matrix[i][j] == []:
                break

            if next_matrix == 'M':
                current_pointer_matrix = pM
                current_matrix = 'M'
            elif next_matrix == 'Y':
                current_pointer_matrix = pYY
                current_matrix = 'Y'
            else:
                current_pointer_matrix = pXX
                current_matrix = 'X'

        return seq1[::-1], seq2[::-1], indices1[::-1], indices2[::-1], score


class Container(ABC):
    def __init__(self, file_name):
        logging.basicConfig(filename='single_sentence_time_aligner.log', format='%(asctime)s :: %(levelname)s :: %(message)s')
        with open(file_name, 'r') as f:
            self.raw = f.read()
        # words as they are in the source file
        self.words = []
        # normalized words (lower case, no diacritics)
        self.normalized = []
        self._extract()

    # this method will extract information form the raw file representation
    def _extract(self):
        pass

    def get_text(self):
        return self.words

    # given a list of indices returns words on this positions
    # if the index is negative (empty string in alignment) than returned empty string := shared.EMPTY_STRING
    def get_text_range(self, indices, clean=False):
        # this method can also be called with int
        indices = [indices] if isinstance(indices, int) else indices
        result = []
        for i in indices:
            if isinstance(i, list):
                result.extend(self.get_text_range(i, clean))
            else:
                if not clean:
                    result.append(self.words[i] if -1 < i < len(self.words) else shared.EMPTY_STRING)
                else:
                    if -1 < i < len(self.words):
                        result.append(self.words[i])
        # if not clean:
        #     return [self.words[i] if -1 < i < len(self.words) else shared.EMPTY_STRING for i in indices]
        # return [self.words[i] for i in indices if -1 < i < len(self.words)]
        return result

    # create one string out of the list
    def get_text_range_flat(self, indices, clean=False):
        return ' '.join(self.get_text_range(indices, clean))

    def get_normalized(self):
        return self.normalized

    # the same as for text but now for normalized text
    def get_normalized_range(self, indices, clean=False):
        # this method can also be called with int
        indices = [indices] if isinstance(indices, int) else indices
        if not clean:
            return [self.normalized[i] if -1 < i < len(self.normalized) else shared.EMPTY_STRING for i in indices]
        return [self.normalized[i] for i in indices if -1 < i < len(self.normalized)]

    def get_normalized_range_flat(self, indices, clean=False):
        return ''.join(self.get_normalized_range(indices, clean))


# class that will contain information from one vertical file
# due to the vertical structure of the transcript we will allow to use indices to operate on index level
# ... like get punctuation/sentence_ending  using indices
# here we also have flat methods that instead of lists return strings
class VerticalFile(Container):
    def __init__(self, file_name):
        # indices are strings
        self.indices = []
        # this list will give indices in self.words
        # self.sentence_endings[i] = k says that at k-th index in self.words the sentence ends
        self.sentence_endings = []
        # punc after the word ... this will be a list of strings .. empty string tells that there was no punc after
        # the word i ... self.words[i]
        self.punctuations = []
        super().__init__(file_name)
        if self.words == []:
            logging.error(f'{file_name} : empty vertical')

    def _extract(self):
        words, indices, endings, speakers = [], [], [], []
        for line in self.raw.split('\n'):
            #if len(line.split('\t')) < 4:
            if len(line.split('\t')) < 3:
                continue
            #word, index, speaker, sentence_ending = line.split('\t')
            word, index, speaker = line.split('\t')
            words.append(word)
            indices.append(index)
            endings.append('') #endings.append(sentence_ending) ### WARN not in data, expected s at the end of sentence !!!
            speakers.append(speaker)

        words_wo_punc, indices_wo_punc, endings_wo_punc, speakers_wo_punc, punc = [], [], [], [], []
        for word, index, sentence_ending, speaker in zip(words, indices, endings, speakers):

            if word in shared.punctuation and punc != []:
                punc[-1] = word
                endings_wo_punc[-1] = sentence_ending == 's'
            else:
                words_wo_punc.append(word)
                indices_wo_punc.append(index)
                speakers_wo_punc.append(speaker)
                endings_wo_punc.append(sentence_ending == 's')
                punc.append('')

        self.speakers = speakers_wo_punc
        self.words = words_wo_punc
        # word normalization
        for w in words_wo_punc:
            # if word represents a number
            if w in shared.abbreviation_dict.keys():
                w = shared.abbreviation_dict[w]
            if w.isnumeric():
                w = num2words(int(w), lang='cz').replace(' ', '')
            self.normalized.append(unidecode(w.lower()).lower())

        self.indices = indices_wo_punc
        self.sentence_endings = endings_wo_punc
        self.punctuations = punc

    @staticmethod
    def _check_index(index):
        # here passed index can be an int or a list of ints (this is done for convenience when solving window mappings)
        # however list of more than one element is not allowed
        if isinstance(index, list):
            if len(index) > 1:
                raise Exception('Index is a list of more than one element.')
            index = index[0]
        return index

    def get_punctuation_by_index(self, index):
        index = self._check_index(index)
        return shared.UNKNOWN if index < 0 else self.punctuations[index]

    def get_id_by_index(self, index):
        index = self._check_index(index)
        return shared.UNKNOWN if index < 0 else self.indices[index]

    def get_sentence_boundary_by_index(self, index):
        index = self._check_index(index)
        return shared.UNKNOWN if index < 0 else self.sentence_endings[index]

    def get_sentence_boundaries_range_flat(self, indices):
        if isinstance(indices, int):
            indices = [indices]
        return ''.join([self.sentence_endings[i] if i > -1 else shared.UNKNOWN for i in indices])

    def get_speaker_by_index(self, index):
        index = self._check_index(index)
        return self.speakers[index] if index >= 0 else shared.UNKNOWN


# class that will contain information from one transcription file
# due to the vertical structure of the transcript we will allow to use indices to operate on index level
# ... like get start/end time using indices
class TranscriptionFile(Container):
    def __init__(self, file_name):
        self.starting_times = []
        self.ending_times = []
        self.normalized = []
        super().__init__(file_name)
        if self.words == []:
            logging.error(f'{file_name} : empty transcript')

    def _extract(self):
        for line in self.raw.split('\n'):
            if line == '':
                break
            start, end, word, _, _, _ = line.split('\t')
            self.words.append(word)
            self.normalized.append(unidecode(word.lower()))
            self.starting_times.append(start)
            self.ending_times.append(end)

    def get_starts_ends_range(self, indices):
        if isinstance(indices, int):
            indices = [indices]
        starts = [float(self.starting_times[i]) for i in indices if i > -1]
        ends = [float(self.ending_times[i]) for i in indices if i > -1]
        return starts[0] if starts else -1, ends[-1] if ends else -1


def display_alignment(vertical_indices, recognized_indices, vertical_obj=None, recognized_obj=None, f=sys.stdout):
    zipped = list(zip(vertical_indices, recognized_indices))
    # obtain max len of the words to get nice output
    max_len = 0
    for v_index, r_index in zipped:
        v_len = len(vertical_obj.get_normalized_range_flat(v_index))
        max_len = v_len if max_len < v_len else max_len

        r_len = len(recognized_obj.get_normalized_range_flat(r_index))
        max_len = r_len if max_len < r_len else max_len

    # max_len = max([max(len(vertical_obj.get), len()) for v_index, r_index in zipped])
    for i, (i1, i2) in enumerate(zipped):
        l1 = vertical_obj.get_normalized_range_flat(i1)
        l2 = recognized_obj.get_normalized_range_flat(i2)
        d = distance(l1, l2)
        output = '{:>{length}} {} {:>{max_len}} {} {:<{max_len}} {} {}'
        # D is a delimiter
        D = "." * max_len
        length = int(np.log(len(zipped)))
        if d == 0:
            # identical words
            l1 = vertical_obj.get_text_range_flat(i1, clean=True)
            print(output.format(i, "*", " ", l1.center(max_len, '.'), " ", "*", ' ', max_len=max_len, length=length), file=f)
        else:
            # different words
            l1 = vertical_obj.get_text_range_flat(i1)
            l2 = recognized_obj.get_text_range_flat(i2)
            print(output.format(i, "M", l1, D, l2, "J", d, max_len=max_len, length=length), file=f)


def solve_window_alignment(trans_indices, vert_indices, trans_inst, vert_inst):
    # detect "one to many" case, we transcription misheared the word, for example
    # elephant  ... el
    #    %      ... he
    #    %      ... fat

    # window_mappings[i] = [k, l, m ...] where k, l, m  ... are indices to the index arrays m_indices and j_indices
    # ... so  matyas_example.get_text_range_flat(m_indices[k]) is some word ... 😭
    window_mappings = []

    # the windows may overlap ... but this will not be a problem
    # transcribed word may be related to two original words
    # in this situation [word1 {word2] word2} where [word1 word2] will relate to one original word
    # {word2 word3} will relate to other original word ... start and end time will not overlap

    trans_indices = list(trans_indices)
    vert_indices = list(vert_indices)

    for i, (k, l) in enumerate(zip(vert_indices, trans_indices)):
        m = vert_inst.get_normalized_range_flat(k)
        j = trans_inst.get_normalized_range_flat(l)
        if m != j and not (shared.EMPTY_STRING in m or shared.EMPTY_STRING in j):
            # now we have word mismatch ... go up/down and collect all blanks

            # go up along the vertical
            before = []
            j = i
            while j > 1 and shared.EMPTY_STRING in vert_inst.get_normalized_range_flat(vert_indices[j - 1]):
                before.append((
                    vert_inst.get_normalized_range_flat(vert_indices[j - 1]),
                    trans_inst.get_normalized_range_flat(trans_indices[j - 1]),
                    j - 1
                ))
                j -= 1

            # go down along the vertical
            after = []
            j = i
            while j < len(vert_indices) - 1 and shared.EMPTY_STRING in vert_inst.get_normalized_range_flat(vert_indices[j + 1]):
                after.append((
                    vert_inst.get_normalized_range_flat(vert_indices[j + 1]),
                    trans_inst.get_normalized_range_flat(trans_indices[j + 1]),
                    j + 1
                ))
                j += 1

            # if we have any blanks in the neighbourhood of matyas word
            if len(after) + len(before) > 0:
                m_word_true = vert_inst.get_normalized_range_flat(k)
                m_word = m_word_true

                # chose best for j_word
                best_match = trans_inst.get_normalized_range_flat(l)
                arrays = [before, after]
                # parts of the final window
                before_final, after_final = [], []
                while True:
                    prefixes, suffixes = arrays
                    prefix = prefixes[0][1] if prefixes != [] else ''
                    suffix = suffixes[0][1] if suffixes != [] else ''
                    # try to improve alignment by adding prefix/suffix
                    improvement = np.argmin([
                        distance(m_word_true, prefix + best_match) if prefixes else float('inf'),
                        # add prefix if exists
                        distance(m_word_true, best_match + suffix) if suffixes else float('inf'),
                        # add suffix if exists
                        distance(m_word_true, prefix + best_match + suffix) if prefixes and suffixes else float('inf'),
                        # add both if exist
                        distance(m_word_true, best_match)  # add nothing
                    ])
                    if improvement == 0:
                        before_final.append(prefixes[0])
                        best_match = prefix + best_match
                        m_word = shared.EMPTY_STRING * len(prefix) + m_word
                        if len(prefixes) == 1:
                            break
                        arrays = [prefixes[1:], []]
                    elif improvement == 1:
                        after_final.append(suffixes[0])
                        best_match = best_match + suffix
                        m_word = m_word + shared.EMPTY_STRING * len(suffix)
                        if len(suffixes) == 1:
                            break
                        arrays = [[], suffixes[1:]]
                    elif improvement == 2:
                        before_final.append(prefixes[0])
                        after_final.append(suffixes[0])
                        best_match = prefix + best_match + suffix
                        m_word = shared.EMPTY_STRING * len(prefix) + m_word + shared.EMPTY_STRING * len(suffix)
                        if len(suffixes) == len(prefixes) == 1:
                            break
                        arrays = [
                            prefixes[1:] if len(prefixes) > 1 else [],
                            suffixes[1:] if len(suffixes) > 1 else []
                        ]
                    else:
                        # can not improve further
                        # since we use edit distance triangle inequality holds and we can stop
                        break
                # create a window that aligns matyas word with blanks to jans words
                window = before_final[::-1]
                window.append(
                    (vert_inst.get_normalized_range_flat(k), trans_inst.get_normalized_range_flat(l), i))
                window.extend(after_final)

                j_word = best_match
                j_word_orig = trans_inst.get_normalized_range_flat(l)
                # normalized diff
                dist = distance(m_word_true, j_word)
                norm_dist = dist / len(m_word_true)
                if distance(m_word, j_word) >= distance(m_word_true,
                                                        j_word) and norm_dist < 0.65 and j_word != j_word_orig:
                    # print(f'+  {dist:>2}  true={m_word_true:>19}   {m_word:>24}   jan={j_word:>18}  {window}')
                    window_mappings.append([w[-1] for w in window])

    # now need to update alignment
    for window in window_mappings:
        # find non empty m_word in window
        # this non empty word will be mapped to the whole window of jan's words
        words = vert_inst.get_text_range([vert_indices[i] for i in window])
        non_empty_index_in_window = [shared.EMPTY_STRING not in w for w in words].index(True)
        non_empty_index_glob = window[non_empty_index_in_window]

        # now we create alignment with own hands
        # in the place where empty string is aligned to some word we replace index of this word by -1 (done in for cycle)
        # in the place where non empty word is aligned to some word we place a list of indices such that concatenating
        # words on these indices will give a some similar word to the original one (done in next two lines)
        vert_indices[non_empty_index_glob] = [vert_indices[i] for i in window if vert_indices[i] > -1]
        trans_indices[non_empty_index_glob] = [trans_indices[i] for i in window if trans_indices[i] > -1]
        for ind in window:
            if ind == non_empty_index_glob:
                continue
            vert_indices[ind] = -1
            trans_indices[ind] = -1

    vert_indices_updated = []
    trans_indices_updated = []
    # remove blanks that are aligned to each other
    for m, j in zip(vert_indices, trans_indices):
        if m == j == -1:
            continue
        vert_indices_updated.append(m)
        trans_indices_updated.append(j)
    # display_alignment(vert_indices_updated, trans_indices_updated, vert_inst, trans_inst)
    return vert_indices_updated, trans_indices_updated, len(window_mappings)


def extract_sentences(vert_indices_updated, trans_indices_updated, vert_inst, trans_inst):
    # now extract sentences from the alignment
    sentences = [Sentence()]
    # at this step in matyas file we do not have multi index
    # display_alignment(vert_indices_updated, trans_indices_updated, vert_inst, trans_inst)
    for i, (m_i, j_i) in enumerate(zip(vert_indices_updated, trans_indices_updated)):
        # print(sentences[-1].m_indices)
        start_time, end_time = trans_inst.get_starts_ends_range(j_i)
        # here multi index can appear
        orig_word = vert_inst.get_normalized_range_flat(m_i)
        transcribed_word = trans_inst.get_normalized_range_flat(j_i)
        # we are at the beginning of the new sentence and original word is aligned to an empty string
        # can be a case of preposition + noun problem
        #   v  ... %
        #  nem ... vnem
        if sentences[-1].start == -1 and start_time < 0 and shared.EMPTY_STRING == transcribed_word and shared.EMPTY_STRING != orig_word:
            # if we are not at the end of the text file
            if i < len(vert_indices_updated) - 1:
                # add next word
                orig_word += vert_inst.get_normalized_range_flat(vert_indices_updated[i + 1])
                transcribed_word += trans_inst.get_normalized_range_flat(trans_indices_updated[i + 1])
            else:
                continue
            d = distance(orig_word, transcribed_word)
            if d / len(orig_word) < PERC:
                # yes we are in case of prep + noun
                #   v  ... %
                #  nem ... vnem
                # first word in the sentence is a preposition
                start_time, _ = trans_inst.get_starts_ends_range(trans_indices_updated[i + 1])
            else:
                # now the situation is that we are at the beginning of the new sentence but
                # we do not know its starting time
                # try to fix it by looking at the ending time of the previous word
                if len(sentences) > 1:
                    start_time = sentences[-2].end
                # else:
                # can not fix and len of total number of sentences is at most one
                #  ... there is an invariant that at each time we have at least one sent
                # continue
                # # thus delete new (empty) sentence and continue to write to the previous sentence
                # del sentences[-1]
                # # remove ending time
                # sentences[-1].end = 0

        if sentences[-1].start == -1 and ((isinstance(m_i, int) and m_i >= 0) or (isinstance(m_i, list) and len(m_i) == 1 and m_i[0] >= 1)):
            sentences[-1].start = start_time

        if vert_inst.get_text_range_flat(m_i) != shared.EMPTY_STRING:
            sentences[-1].vert_indices.append(m_i)

            # if trans_inst.get_text_range_flat(j_i) != shared.EMPTY_STRING:
            sentences[-1].trans_indices.append(j_i)

        sentence_ended = vert_inst.get_sentence_boundary_by_index(m_i)
        if sentence_ended != shared.UNKNOWN and sentence_ended:
            # if end time is undefined
            if end_time == -1:
                # check if we are not at the end
                if i >= len(vert_indices_updated) - 1:
                    print('Custom "warning" : No ending time given for the LAST sentence, since neither end time of the'
                          ' last word in the current sentence nor starting time for the NEXT sentence '
                          '(because there is even no next word) exists. Thus this sentence will not have audio '
                          'representation. It would not be good to set ending time to the length of audio recording'
                          'since it can have non empty offset (non empty means that it has some speech, empty means'
                          'there is only silence in the offset).')
                    continue
                # we can try to pick next word
                # since maybe we have a case where only last word of the sentence is not recognized
                # but the next word is fine
                next_start, _ = trans_inst.get_starts_ends_range(trans_indices_updated[i + 1])
                # if next word has well defined starting time
                if next_start != -1:
                    sentences[-1].end = next_start
                    sentences.append(Sentence())
                else:
                    # the next word was not recognized also
                    # continuing we will merge two sentences
                    continue
            else:
                # end time is well defined
                sentences[-1].end = end_time
                # this condition will not allow adding empty sentence at the end
                if i < len(vert_indices_updated) - 1:
                    sentences.append(Sentence())
    return sentences


def score_alignment(v_ind, t_ind, v_inst, t_inst):
    cnt_missed = 0
    data_size = 0
    normalized_edit_distances = []
    normalized_edit_distances_with_gaps = []
    for i, (v_i, t_i) in enumerate((zip(v_ind, t_ind))):
        ver_word = v_inst.get_normalized_range_flat(v_i)
        l = len(ver_word)
        if shared.EMPTY_STRING not in ver_word and len(ver_word) > 2:
            trans_word = t_inst.get_normalized_range_flat(t_i)
            if shared.EMPTY_STRING not in trans_word:
                if ver_word == trans_word:
                    normalized_edit_distances.append(0)
                    normalized_edit_distances_with_gaps.append(0)
                else:
                    normalized_edit_distances.append(distance(ver_word, trans_word) / l)
                    normalized_edit_distances_with_gaps.append(distance(ver_word, trans_word) / l)
            else:
                cnt_missed += 1
                normalized_edit_distances_with_gaps.append(1)
            data_size += 1
    print(cnt_missed)
    print(data_size)
    # print(normalized_edit_distances)
    # print(normalized_edit_distances_with_gaps)
    # print(np.average(normalized_edit_distances_with_gaps))
    # print(np.average(normalized_edit_distances))
    return cnt_missed / data_size, normalized_edit_distances, normalized_edit_distances_with_gaps

# %%
if __name__ == '__main__':
    # %%
    args = parser.parse_args([] if "__file__" not in globals() else None)
    with open(args.yaml_config, 'r') as file:
        # The FullLoader parameter handles the conversion from YAML
        # scalar values to Python the dictionary format
        config = yaml.load(file, Loader=yaml.FullLoader)

    PERC = config['perc']
    start_penalty = config['start_penalty']
    extend_penalty = config['extend_penalty']
    mult = config['mult']
    vert_inst = VerticalFile(args.vertical)
    trans_inst = TranscriptionFile(args.transcript)

    aligner = Aligner(start_penalty=-5, extend_penalty=-4, mult=3)
    # here we are passing text from transcription and vertical and get indices to this text
    # further we will operate on indices
    _, _, vert_indices, trans_indices, score = aligner.align(trans_inst.get_normalized(), vert_inst.get_normalized())

    # %%
    # instances of vertical and transcription
    # display_alignment(vert_indices, trans_indices, vert_inst, trans_inst)
    vert_indices_updated, trans_indices_updated, solved_cnt = solve_window_alignment(trans_indices, vert_indices, trans_inst, vert_inst)
    sentences = extract_sentences(vert_indices_updated, trans_indices_updated, vert_inst, trans_inst)
    # %%
    # extract sentence timings with score
    # score will be used to infer if the sentence is correct or not
    output = []
    output_explained = []
    total_dist = 0
    if len(sentences[-1].vert_indices) == 0:
        del sentences[-1]

    if not os.path.isdir(args.output_dir):
        os.mkdir(args.output_dir)

    with open(os.path.join(args.output_dir, 'debug.txt'), 'w') as f:
        display_alignment(vert_indices_updated, trans_indices_updated, vert_inst, trans_inst, f=f)

    with open(os.path.join(args.output_dir, 'stats.tsv'), 'w') as f:
        missed_percentage, normalized_edit_distances, normalized_edit_distances_with_gaps = score_alignment(vert_indices_updated, trans_indices_updated, vert_inst, trans_inst)
        head = ['missed_percentage', 'median_normalized_dist', 'normalized_dist_75', 'normalized_dist_90', 'median_normalized_dist_including_gaps', 'normalized_dist_with_gaps_75', 'normalized_dist_with_gaps_90', 'windows_solved']
        stats = [
            missed_percentage,
            np.median(normalized_edit_distances),
            np.percentile(normalized_edit_distances, 75),
            np.percentile(normalized_edit_distances, 90),

            np.median(normalized_edit_distances_with_gaps),
            np.percentile(normalized_edit_distances_with_gaps, 75),
            np.percentile(normalized_edit_distances_with_gaps, 90),

            solved_cnt/max(vert_indices)
        ]
        stats = [f'{x:>.3f}' for x in stats]
        print('\t'.join(head), file=f)
        print('\t'.join(stats), file=f)

    audio = pydub.AudioSegment.from_mp3(args.mp3)
    for k, sentence in enumerate(sentences):
        if len(sentence.vert_indices) == 0:
            print(f'Error in sentence {k}, it is empty, and not the last sentence. '
                  f'Total number of sentences is {len(sentences)}')
            continue
        audio_segment = audio[sentence.start * 1000: sentence.end * 1000]
        sentence_duration = sentence.end - sentence.start
        asr_sentence = []
        words = []
        speakers = set()
        pretty_sentence = []
        sentence_dist = 0
        cnt_missed_words = 0
        avg_sentence_duration = 0
        total_chars = 0
        missed_chars = 0
        recognized = 0
        for m_i, j_i in zip(sentence.vert_indices, sentence.trans_indices):
            trans_word_norm = trans_inst.get_normalized_range_flat(j_i)
            vert_word_norm = vert_inst.get_normalized_range_flat(m_i)
            word = vert_inst.get_text_range_flat(m_i)
            punc = vert_inst.get_punctuation_by_index(m_i)
            speaker = vert_inst.get_speaker_by_index(m_i)
            s, e = trans_inst.get_starts_ends_range(j_i)
            s = s - sentence.start if s > 0 else s
            e = e - sentence.start if e > 0 else e
            recognized += (e - s) if 0 < s < e else 0
            avg_word_duration = (e - s) / len(word) if 0 <= s < e else 0
            avg_sentence_duration += avg_word_duration
            if shared.EMPTY_STRING not in word:
                total_chars += len(word)
                if trans_word_norm == shared.EMPTY_STRING:
                    dist = -1
                    cnt_missed_words += 1
                    missed_chars += len(word)
                else:
                    dist = np.clip(distance(trans_word_norm, vert_word_norm) / len(word), 0, 1)
                    sentence_dist += dist
                words.append(f'{word}\t{s:.3f}\t{e:.3f}\t{dist:.3f}\t{avg_word_duration:.3f}\t{speaker}')
                asr_sentence.append(word.upper())
                speakers.add(speaker)
                word += ' ' + punc if punc != shared.UNKNOWN else ''
                pretty_sentence.append(word)

        if pretty_sentence != []:
            sentence_dir = os.path.join(args.output_dir, f'{k}')
            if not os.path.isdir(sentence_dir):
                os.mkdir(sentence_dir)

            name = os.path.basename(args.mp3).replace('.mp3', '')
            # audio_segment.export(out_f=os.path.join(sentence_dir, name + '.wav'), format='wav')
            # with open(os.path.join(sentence_dir, name + '.asr'), 'w') as f:
            #     print(' '.join(asr_sentence), file=f)
            with open(os.path.join(sentence_dir, name + '.prt'), 'w') as f:
                print(' '.join(pretty_sentence), file=f)
            with open(os.path.join(sentence_dir, name + '.words'), 'w') as f:
                print('\n'.join(words), file=f)
            with open(os.path.join(sentence_dir, name + '.speakers'), 'w') as f:
                print(f'Speakers: {", ".join(speakers)}', file=f)

            # write some stats
            with open(os.path.join(sentence_dir, 'stats.tsv'), 'w') as f:
                # can recover original (non normalized stats) by multiplying by total_words
                stats = dict(
                    words_cnt=len(words),
                    chars_cnt=total_chars,
                    duration=sentence_duration,
                    speakers_cnt=len(speakers),
                    missed_words=cnt_missed_words,
                    missed_words_percentage=cnt_missed_words / len(words),
                    missed_chars=missed_chars,
                    missed_chars_percentage=missed_chars / total_chars,
                    sentence_avg_edit_dist=sentence_dist / len(words),
                    sentence_avg_char_in_word_duration=avg_sentence_duration / len(words),
                    sentence_avg_char_in_sentence_duration_in_ms=total_chars / (sentence_duration * 1000),
                    recognized_sound_coverage=recognized / sentence_duration,
                    correct_end=sentence.end != 0
                )
                for k, v in stats.items():
                    print(f'{k}\t{v:.3f}', file=f)

    # for k, sentence in enumerate(sentences):
    #     if len(sentence.vert_indices) == 0:
    #         print(f'Error in sentence {k}, it is empty, and not the last sentence. '
    #               f'Total number of sentences is {len(sentences)}')
    #         continue
    #     start = f'{sentence.start:>0.3f}'
    #     end = f'{sentence.end:>0.3f}'
    #     text_orig = []
    #     text_orig_normalized = [vert_inst.get_normalized_range_flat(m_i) for m_i in sentence.vert_indices]
    #     text_trans = [trans_inst.get_text_range_flat(j_i) for j_i in sentence.trans_indices]
    #     word_ids = []
    #     edit_distance = distance(' '.join(text_orig_normalized), ' '.join([trans_inst.get_normalized_range_flat(j_i) for j_i in sentence.trans_indices]))
    #     total_dist += edit_distance
    #
    #     for m_i in sentence.vert_indices:
    #         word = vert_inst.get_text_range_flat(m_i)
    #         punc = vert_inst.get_punctuation_by_index(m_i)
    #         word += punc if punc != shared.UNKNOWN else ''
    #         text_orig.append(word)
    #         word_ids.append(vert_inst.get_id_by_index(m_i))
    #
    #     score = (float(sentence.end) * 1000 - float(sentence.start) * 1000) / sum([len(w) for w in text_orig])
    #     if word_ids != []:
    #         output.append(
    #             f'{k}\t{start}\t{end}\t{word_ids[0]}\t{word_ids[-1]}\t{score:.3f}\t{edit_distance}'
    #         )
    #         output_explained.append(
    #             f"{k}\torig\t{' '.join(text_orig)}\n"
    #             f"{k}\tnorm\t{' '.join(text_orig_normalized)}\n"
    #             f"{k}\ttransc\t{' '.join(text_trans)}\n"
    #             f"{k}\tstart\t{start}\n"
    #             f"{k}\tend\t{end}\n"
    #             f"{k}\tcharlen\t{sum([len(w) for w in text_orig_normalized])}\n"
    #             f"{k}\tmslen\t{float(sentence.end) * 1000 - float(sentence.start) * 1000}\n"
    #             f"{k}\tscore\t{(float(sentence.end) * 1000 - float(sentence.start) * 1000) / sum([len(w) for w in text_orig]):.2f}\n"
    #             f"{k}\tdist\t{edit_distance}\n"
    #         )

    # with open(args.output, 'w') as f:
    #     f.write(f'{total_dist/len(sentences):.3f}')
    #     f.write('\n')
    #     f.write('\n'.join(output))
    #
    # with open(args.output.replace('.txt', '-explained.txt'), 'w') as f:
    #     # f.write(f'{score}' + '\n')
    #     f.write(f'{total_dist:.3f}')
    #     f.write('\n')
    #     f.write('\n'.join(output_explained))
    # %%
    # from pydub import AudioSegment
    # import shutil
    # import os
    # base_path = '/home/stankvla/Projects/Python/Comp-in-MT/align/working_dir/output'
    # if os.path.isdir(base_path):
    #     shutil.rmtree(base_path)
    # os.mkdir(base_path)
    #
    # for i, sentence in enumerate(sentences):
    #     start = vert_inst.get_id_by_index(sentence.vert_indices[0])
    #     end = vert_inst.get_id_by_index(sentence.vert_indices[-1])
    #     t1 = float(sentence.start) * 1000
    #     t2 = float(sentence.end) * 1000
    #     newAudio = AudioSegment.from_mp3("/home/stankvla/Projects/Python/Comp-in-MT/align/lindat/2013ps/audio/2013/12/19/2013121913081322.mp3")
    #     newAudio = newAudio[t1:t2]
    #     newAudio.export(f'{base_path}/{i}_{start}_{end}.wav', format="wav")
    #
