#!/usr/bin/env python
import os

def Replace(file_path, old_string, new_string):
  with open(file_path, 'r') as f:
    content = f.read()
  with open(file_path, 'w') as f:
    f.write(content.replace(old_string, new_string))


def FindAndReplace(root_dir, old_string, new_string):
  root_dir = os.path.abspath(root_dir)
  for root, _, files in os.walk(root_dir):
    for f in files:
      file_path = os.path.join(root, f)
      Replace(file_path, old_string, new_string)

