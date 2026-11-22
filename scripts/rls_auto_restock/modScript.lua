-- rls_auto_restock mod entry: load the companion extension outside BeamNG's modScript loader wrapper.
setExtensionUnloadMode("rlsAutoRestock", "manual")
core_jobsystem.create(function(job)
  job.sleep(0.25)
  if not extensions.isExtensionLoaded("rlsAutoRestock") then
    extensions.load("rlsAutoRestock")
  end
end)
