//! a

use std::{num::NonZeroUsize, path::PathBuf};

use blueos_domain::{Domain, Effect, Outcome};
use blueos_jobs::{JobEnd, JobId, Jobs};

struct DiskUsage;

#[derive(Clone)]
struct DiskUsageSnapshot {
    job_id: u128,
    jobs: Jobs,
}

enum DiskUsageCommand {
    Usage {
        path: PathBuf,
        depth: Option<NonZeroUsize>,
        include_files: bool,
        min_size_bytes: Option<NonZeroUsize>,
    },
}

struct DiskNode {
    name: String,
    path: PathBuf,
    size_bytes: usize,
    is_dir: bool,
    children: Vec<DiskNode>,
}

enum DiskUsageIoResult {
    Usage {
        job_id: JobId,
        root: DiskNode,
        generated_at: f64,
        depth: usize,
        include_files: bool,
        min_size_bytes: usize,
    },
}

#[derive(Clone)]
struct DiskUsageTick;

struct DiskUsageObservedFact;

enum DiskUsageEvent {}

#[derive(Clone)]
enum DiskUsageIoRequest {
    Usage {
        path: PathBuf,
        depth: Option<NonZeroUsize>,
        include_files: bool,
        min_size_bytes: Option<NonZeroUsize>,
    },
}

#[derive(Clone, PartialEq, Eq, Hash)]
struct DiskUsageTimerKey(usize);

impl Domain for DiskUsage {
    type Snapshot = DiskUsageSnapshot;
    type Request = DiskUsageCommand;
    type IoResult = DiskUsageIoResult;
    type Tick = DiskUsageTick;
    type ObservedFact = DiskUsageObservedFact;
    type Event = DiskUsageEvent;
    type IoRequest = DiskUsageIoRequest;
    type TimerKey = DiskUsageTimerKey;

    fn handle(
        snapshot: &mut Self::Snapshot,
        command: blueos_domain::Command<
            Self::Request,
            Self::IoResult,
            Self::Tick,
            Self::ObservedFact,
        >,
        _now: blueos_domain::Now,
    ) -> blueos_domain::Decision<Self> {
        match command {
            blueos_domain::Command::Request(command) => match command {
                DiskUsageCommand::Usage {
                    path,
                    depth,
                    include_files,
                    min_size_bytes,
                } => Outcome::Applied {
                    events: vec![],
                    effects: vec![Effect::Io(DiskUsageIoRequest::Usage {
                        path,
                        depth,
                        include_files,
                        min_size_bytes,
                    })],
                },
            },
            blueos_domain::Command::IoResult(result) => match result {
                DiskUsageIoResult::Usage {
                    job_id,
                    root,
                    generated_at,
                    depth,
                    include_files,
                    min_size_bytes,
                } => {
                    let _ = snapshot.jobs.end(job_id, JobEnd::Succeeded);
                    Outcome::Applied {
                        events: vec![],
                        effects: vec![],
                    }
                }
            },
            blueos_domain::Command::Tick(_) => Outcome::Rejected {
                reason: Box::new(std::io::Error::new(
                    std::io::ErrorKind::Unsupported,
                    "unimplemented",
                )),
            },
            blueos_domain::Command::ObservedFact(_) => Outcome::Rejected {
                reason: Box::new(std::io::Error::new(
                    std::io::ErrorKind::Unsupported,
                    "unimplemented",
                )),
            },
        }
    }

    fn io_failed(
        request: Self::IoRequest,
        error: blueos_domain::IoError,
    ) -> blueos_domain::Command<Self::Request, Self::IoResult, Self::Tick, Self::ObservedFact> {
        todo!()
    }
}
