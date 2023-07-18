import argparse
import concurrent.futures
import io
import os
import json
import logging
import random
import sched
import string
import sys
import time

logging.basicConfig(
    level=logging.DEBUG, stream=sys.stderr,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('log_generator')
logger.setLevel(logging.DEBUG)

_TAG_PREFIX = 'performance-benchmarking'
_DEFAULT_CHARS = string.ascii_letters + string.digits


def _log_error_and_sleep(err, sleep_seconds):
    """"""
    logger.error('Encountered error: %s.', err)
    logger.info('Sleep for %d seconds then try again.', sleep_seconds)
    time.sleep(sleep_seconds)


def _random_string(size, chars=None):
    """"""
    random.seed(time.time())
    return ''.join(random.choice(_DEFAULT_CHARS) for _ in range(size))


def _construct_log_record(log_size_in_bytes):
    """"""
    return _random_string(log_size_in_bytes)


def _construct_log_tag(log_size_in_bytes, log_rate):
    """"""
    return '{prefix}.size-{size}-rate-{rate}'.format(
        prefix=_TAG_PREFIX,
        size=log_size_in_bytes,
        rate=log_rate)


class LogGenerator(object):
    """"""

    @property
    def log_size_in_bytes(self):
        return self._log_size_in_bytes

    @property
    def log_rate(self):
        return self._log_rate

    @property
    def log_agent_input(self):
        return self._log_agent_input

    def __init__(self,
                 log_size_in_bytes,
                 log_rate,
                 log_agent_input):
        """"""
        self._log_rate = log_rate
        self._log_size_in_bytes = log_size_in_bytes
        self._log_record = _construct_log_record(log_size_in_bytes)
        self._log_tag = _construct_log_tag(log_size_in_bytes, log_rate)
        self._log_agent_input = log_agent_input

    def _construct_full_log_message(self):
        """"""
        self._log_record = _construct_log_record(self._log_size_in_bytes)
        return '{timestamp} {log_record}'.format(
            timestamp=time.time(),
            log_record=self._log_record)

    def send_logs(self):
        """"""
        start_time = time.time()
        with self._log_agent_input:
            for _ in range(self._log_rate):
                self._log_agent_input.send_message(
                    self._construct_full_log_message())
        end_time = time.time()
        logger.info('Successfully sent this log message %d times:\n%s.',
                    self._log_rate, self._log_record)

        if end_time > start_time + 1:
            logger.error(
                'Detected overruns. Failed to keep up with the expected QPS.')

    def run(self, count: int):
        """Generate logs for count seconds. If count <= 0, do so indefinitely."""
        event_scheduler = sched.scheduler(time.time, time.sleep)
        event_scheduler.enter(1, 1, schedule_event_and_send_logs,
                              argument=(event_scheduler, self, count))
        event_scheduler.run()


class LogAgentInput():
    def send_message(self, log_message):
        pass

    def ___enter__(self):
        pass

    def __exit__(self, type_, value_, traceback_):
        pass


class TailInput(LogAgentInput):
    def __init__(self, tail_file_location):
        self.tail_file_location = tail_file_location
        self.f = None

    def __enter__(self):
        self.f = open(self.tail_file_location, 'a')
        return self

    def __exit__(self, type_, value_, traceback_):
        self.f.flush()
        self.f.close()
        self.f = None

    def send_message(self, log_message):
        assert isinstance(self.f, io.TextIOWrapper)
        self.f.write(log_message + '\n')


def schedule_event_and_send_logs(scheduler, log_generator, count):
    if count != 1:
        scheduler.enter(1, 1, schedule_event_and_send_logs,
                        argument=(scheduler, log_generator, count - 1))
    log_generator.send_logs()


# Main function.
parser = argparse.ArgumentParser(
    description='Flags to initiate Log Generator.')
parser.add_argument(
    '--log-size-in-bytes', type=int, default=10,
    help='The size of each log entry in bytes for fixed-entry logs.')
parser.add_argument(
    '--log-rate', type=int, default=10,
    help='The number of expected log entries per second for fixed-rate logs.')

parser.add_argument(
    '--tail-file-path', type=str, default='tail_log',
    help='The file to which logs will be written to.')

parser.add_argument(
    '--count', type=int, default=-1,
    help='How many seconds to send logs for. If negative, send indefinitely')

parser.add_argument(
    '--processes', type=int, default=1,
    help='How many processes to use to send logs')


def main():
    random.seed(a=1, version=2)
    args = parser.parse_args()
    logger.info('Parsed args: %s', args)
    futures = []
    with concurrent.futures.ProcessPoolExecutor(
            max_workers=args.processes) as executor:
        for i in range(args.processes):
            log_rate = args.log_rate // args.processes
            if i == 0:
                log_rate += args.log_rate % args.processes
            # input_handler is referring to the file itself
            input_handler = TailInput(args.tail_file_path)
            log_generator = LogGenerator(
                log_size_in_bytes=args.log_size_in_bytes, log_rate=log_rate,
                log_agent_input=input_handler)
            futures.append(executor.submit(log_generator.run, count=args.count))
    for f in futures:
        f.result()


if __name__ == '__main__':
    main()
