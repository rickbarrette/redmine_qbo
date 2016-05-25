#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module BaseBackgroundHelper
  
  # abstact methods to be overriden
  def run; raise "run method is missing"; end
  def success_path; raise "success_path is missing"; end
  def error_path; raise "error_path is missing"; end
  
  # args = {:job_id, :type, :id}
  def self.perform(args)
    job = Job.find_by_id(args[:job_id])
    
    # Call the abstact method passing the service 
    run(Qbo.get_base(args[:type]).service, :id)
    
    job.change_status("succes")  
  end
  
  # Create the job record
  def self.prepare_job(obj)
    Job.create(
      owner:       self.to_s,
      method_name: "perform",
      title:       "Working in Background",
      method_args: { type: obj.type, id: obj.id } ,
      succes_url:  success_path,
      error_url:   error_path,
      succes_type: "user_click",
      error_type:  "user_click"
    )
  end
end
