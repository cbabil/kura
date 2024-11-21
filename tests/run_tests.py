#!/usr/bin/env python3

import unittest
import argparse
import sys
import yaml
import coverage
from concurrent.futures import ThreadPoolExecutor

def load_config():
    with open('test-config.yaml', 'r') as f:
        return yaml.safe_load(f)

def run_test_suite(suite_name, config):
    suite_config = config['test_suites'][suite_name]
    
    if suite_config.get('coverage', False):
        cov = coverage.Coverage()
        cov.start()
        
    loader = unittest.TestLoader()
    suite = loader.discover(f'tests/{suite_name}')
    
    if suite_config.get('parallel', False):
        with ThreadPoolExecutor() as executor:
            executor.map(unittest.TextTestRunner().run, suite)
    else:
        unittest.TextTestRunner().run(suite)
        
    if suite_config.get('coverage', False):
        cov.stop()
        cov.save()
        cov.html_report()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--suite', choices=['unit', 'integration', 'system', 'security', 'all'])
    args = parser.parse_args()
    
    config = load_config()
    
    if args.suite == 'all':
        for suite in config['test_suites']:
            run_test_suite(suite, config)
    else:
        run_test_suite(args.suite, config)

if __name__ == '__main__':
    sys.exit(main()) 