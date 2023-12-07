import os
import shutil
import numpy as np
from unidecode import unidecode
from Levenshtein import distance

EMPTY_STRING = '-'
UNKNOWN = '-'
# this is a manual dict that is used to expand at least some abbreviations
abbreviation_dict = {
    '§': 'paragraf',
    'č': 'číslo',
    'mld': 'miliarda',
    '%': 'procent',
    'tj': 'tojest',
    'sb': 'sbírka',
    'cca': 'cirka',
    'odst': 'odstavec',
    'tzv': 'takzvané',
    'resp': 'respektive',
    'atd': 'a tak dále',
    'hod': 'hodin',
    'tzn': 'to znamená',
    'apod': 'a podobně',
    'kč': 'korun',
    '/': 'lomeno'
}
punctuation = "!\"#&'()*-,:;?[]^_`{|}~."


def create_dir_if_not_exist(path):
    if isinstance(path, str):
        path = [path]
    path_flat = os.path.join(*path)
    if not os.path.exists(path_flat):
        os.makedirs(path_flat)
    return path_flat


def clean_directory_if_exists(path):
    path_flat = path
    if isinstance(path, list):
        path_flat = os.path.join(*path)
    if os.path.isdir(path_flat):
        shutil.rmtree(path_flat)
    return create_dir_if_not_exist(path)


def clean_vertical(source, path):
    banned = ['(', ')', ';', '{', '}', '[', ']']
    cleaned_vertical = []
    with open(source, 'r') as f:
        for line in f:
            word, _, _, _ = line.split('\t')
            if word in banned:
                continue
            cleaned_vertical.append(word)

    cleaned_vertical_path = os.path.join(path)
    with open(cleaned_vertical_path, 'w') as f:
        f.write('\n'.join(cleaned_vertical))
    return path
