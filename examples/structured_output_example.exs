# Structured Output Example with ExLLM and instructor_ex
#
# This example demonstrates how to use ExLLM's structured output capabilities
# to extract and validate data from LLM responses.
#
# Prerequisites:
# 1. Add {:instructor, "~> 0.1.0"} to your dependencies
# 2. Set up your ANTHROPIC_API_KEY environment variable
#
# Run with: mix run examples/structured_output_example.exs

# Ensure instructor is available
unless Code.ensure_loaded?(Instructor) do
  IO.puts("""
  Error: The instructor library is not available.
  
  Please add it to your dependencies:
    {:instructor, "~> 0.1.0"}
  
  Then run: mix deps.get
  """)
  System.halt(1)
end

# Example 1: Simple Email Classification
defmodule EmailClassification do
  use Ecto.Schema
  use Instructor.Validator

  @llm_doc """
  Classification of an email message.
  Determine if the email is spam or not spam, with confidence and reasoning.
  """
  
  @primary_key false
  embedded_schema do
    field :classification, Ecto.Enum, values: [:spam, :not_spam]
    field :confidence, :float
    field :reason, :string
  end

  @impl true
  def validate_changeset(changeset) do
    changeset
    |> Ecto.Changeset.validate_required([:classification, :confidence, :reason])
    |> Ecto.Changeset.validate_number(:confidence, 
        greater_than_or_equal_to: 0.0,
        less_than_or_equal_to: 1.0
      )
    |> Ecto.Changeset.validate_length(:reason, max: 200)
  end
end

# Example 2: Complex User Profile Extraction
defmodule UserProfile do
  use Ecto.Schema
  use Instructor.Validator

  @llm_doc """
  Extract user profile information from text.
  Include all available details about the person.
  """

  @primary_key false
  embedded_schema do
    field :name, :string
    field :email, :string
    field :age, :integer
    field :occupation, :string
    field :location, :string
    
    embeds_many :skills, Skill, primary_key: false do
      field :name, :string
      field :level, Ecto.Enum, values: [:beginner, :intermediate, :advanced, :expert]
      field :years_experience, :integer
    end
    
    embeds_many :interests, Interest, primary_key: false do
      field :name, :string
      field :category, :string
    end
  end

  @impl true
  def validate_changeset(changeset) do
    changeset
    |> Ecto.Changeset.validate_required([:name])
    |> Ecto.Changeset.validate_format(:email, ~r/@/, message: "must be a valid email")
    |> Ecto.Changeset.validate_number(:age, greater_than: 0, less_than: 150)
    |> Ecto.Changeset.cast_embed(:skills, with: &skill_changeset/2)
    |> Ecto.Changeset.cast_embed(:interests, with: &interest_changeset/2)
  end
  
  defp skill_changeset(skill, params) do
    skill
    |> Ecto.Changeset.cast(params, [:name, :level, :years_experience])
    |> Ecto.Changeset.validate_required([:name, :level])
    |> Ecto.Changeset.validate_number(:years_experience, greater_than_or_equal_to: 0)
  end
  
  defp interest_changeset(interest, params) do
    interest
    |> Ecto.Changeset.cast(params, [:name, :category])
    |> Ecto.Changeset.validate_required([:name])
  end
end

# Example 3: Meeting Summary
defmodule MeetingSummary do
  use Ecto.Schema
  use Instructor.Validator

  @llm_doc """
  Structured summary of a meeting transcript.
  Extract key information and organize it clearly.
  """

  @primary_key false
  embedded_schema do
    field :title, :string
    field :date, :string
    field :duration_minutes, :integer
    field :participants, {:array, :string}
    field :summary, :string
    
    embeds_many :key_points, KeyPoint, primary_key: false do
      field :topic, :string
      field :description, :string
      field :priority, Ecto.Enum, values: [:low, :medium, :high]
    end
    
    embeds_many :action_items, ActionItem, primary_key: false do
      field :task, :string
      field :assignee, :string
      field :due_date, :string
      field :status, Ecto.Enum, values: [:pending, :in_progress, :completed]
    end
    
    embeds_many :decisions, Decision, primary_key: false do
      field :decision, :string
      field :rationale, :string
    end
  end

  @impl true
  def validate_changeset(changeset) do
    changeset
    |> Ecto.Changeset.validate_required([:title, :summary])
    |> Ecto.Changeset.validate_number(:duration_minutes, greater_than: 0)
    |> Ecto.Changeset.validate_length(:summary, min: 50, max: 500)
    |> Ecto.Changeset.cast_embed(:key_points, with: &key_point_changeset/2)
    |> Ecto.Changeset.cast_embed(:action_items, with: &action_item_changeset/2)
    |> Ecto.Changeset.cast_embed(:decisions, with: &decision_changeset/2)
  end
  
  defp key_point_changeset(point, params) do
    point
    |> Ecto.Changeset.cast(params, [:topic, :description, :priority])
    |> Ecto.Changeset.validate_required([:topic, :description, :priority])
  end
  
  defp action_item_changeset(item, params) do
    item
    |> Ecto.Changeset.cast(params, [:task, :assignee, :due_date, :status])
    |> Ecto.Changeset.validate_required([:task, :assignee])
  end
  
  defp decision_changeset(decision, params) do
    decision
    |> Ecto.Changeset.cast(params, [:decision, :rationale])
    |> Ecto.Changeset.validate_required([:decision])
  end
end

# Run Examples
defmodule Examples do
  def run do
    IO.puts("\n🚀 ExLLM Structured Output Examples\n")
    
    # Check if ExLLM is configured
    unless ExLLM.configured?(:anthropic) do
      IO.puts("Error: Anthropic is not configured. Please set ANTHROPIC_API_KEY environment variable.")
      System.halt(1)
    end
    
    # Example 1: Email Classification
    IO.puts("1️⃣ Email Classification Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    email_messages = [
      %{
        role: "user",
        content: """
        Classify this email:
        
        Subject: Congratulations! You've won $1,000,000!
        
        Dear Winner,
        
        We are pleased to inform you that your email address has been selected
        in our international lottery. You have won ONE MILLION DOLLARS!
        
        To claim your prize, please send us your bank details and a processing
        fee of $500.
        
        Best regards,
        International Lottery Commission
        """
      }
    ]
    
    case ExLLM.chat(:anthropic, email_messages, 
      response_model: EmailClassification,
      max_retries: 3,
      temperature: 0.1
    ) do
      {:ok, result} ->
        IO.puts("Classification: #{result.classification}")
        IO.puts("Confidence: #{Float.round(result.confidence * 100, 1)}%")
        IO.puts("Reason: #{result.reason}")
        
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    
    # Example 2: User Profile Extraction
    IO.puts("\n\n2️⃣ User Profile Extraction Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    profile_text = """
    Hi everyone! I'm Sarah Chen, a 32-year-old software architect based in San Francisco.
    You can reach me at sarah.chen@techcorp.com. I've been working with distributed systems
    for about 8 years now and consider myself an expert in Elixir and Erlang. I'm also
    advanced in Kubernetes (5 years) and intermediate in Rust (2 years). 
    
    Outside of work, I'm passionate about rock climbing (outdoor sports category) and 
    photography (creative arts). I also enjoy cooking Asian fusion cuisine (culinary arts).
    """
    
    profile_messages = [
      %{
        role: "user",
        content: "Extract the user profile from this text:\n\n#{profile_text}"
      }
    ]
    
    case ExLLM.chat(:anthropic, profile_messages,
      response_model: UserProfile,
      max_retries: 3
    ) do
      {:ok, profile} ->
        IO.puts("Name: #{profile.name}")
        IO.puts("Email: #{profile.email}")
        IO.puts("Age: #{profile.age}")
        IO.puts("Occupation: #{profile.occupation}")
        IO.puts("Location: #{profile.location}")
        
        IO.puts("\nSkills:")
        Enum.each(profile.skills, fn skill ->
          IO.puts("  - #{skill.name}: #{skill.level} (#{skill.years_experience} years)")
        end)
        
        IO.puts("\nInterests:")
        Enum.each(profile.interests, fn interest ->
          IO.puts("  - #{interest.name} (#{interest.category})")
        end)
        
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    
    # Example 3: Meeting Summary
    IO.puts("\n\n3️⃣ Meeting Summary Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    meeting_transcript = """
    Project Status Meeting - January 24, 2025
    Duration: 45 minutes
    Participants: John (PM), Sarah (Lead Dev), Mike (Designer), Lisa (QA)
    
    John: Let's start with the API redesign status.
    
    Sarah: We've completed the authentication module. It's using JWT tokens with 
    refresh capability. The user endpoints are 80% done, just need to add pagination.
    
    Mike: The new UI mockups for the dashboard are ready. I've incorporated the 
    feedback about making the graphs more prominent.
    
    Lisa: I found three critical bugs in the payment flow that need immediate attention.
    We should fix these before the release.
    
    John: Agreed. Sarah, can you prioritize the payment bugs?
    
    Sarah: Yes, I'll assign Tom to fix those by Friday.
    
    John: Great. We're still on track for the February 15th release. Mike, please
    share the mockups with the team by EOD.
    
    Decision made: We'll postpone the advanced analytics feature to v2.1 to ensure
    we meet the deadline with a stable product.
    """
    
    meeting_messages = [
      %{
        role: "user",
        content: "Create a structured summary of this meeting:\n\n#{meeting_transcript}"
      }
    ]
    
    case ExLLM.chat(:anthropic, meeting_messages,
      response_model: MeetingSummary,
      max_retries: 3
    ) do
      {:ok, summary} ->
        IO.puts("Title: #{summary.title}")
        IO.puts("Duration: #{summary.duration_minutes} minutes")
        IO.puts("Participants: #{Enum.join(summary.participants, ", ")}")
        IO.puts("\nSummary: #{summary.summary}")
        
        if length(summary.key_points) > 0 do
          IO.puts("\nKey Points:")
          Enum.each(summary.key_points, fn point ->
            IO.puts("  • [#{String.upcase(to_string(point.priority))}] #{point.topic}")
            IO.puts("    #{point.description}")
          end)
        end
        
        if length(summary.action_items) > 0 do
          IO.puts("\nAction Items:")
          Enum.each(summary.action_items, fn item ->
            due = if item.due_date, do: " (Due: #{item.due_date})", else: ""
            IO.puts("  ✓ #{item.task} - Assigned to: #{item.assignee}#{due}")
          end)
        end
        
        if length(summary.decisions) > 0 do
          IO.puts("\nDecisions:")
          Enum.each(summary.decisions, fn decision ->
            IO.puts("  → #{decision.decision}")
            if decision.rationale, do: IO.puts("    Rationale: #{decision.rationale}")
          end)
        end
        
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    
    # Example 4: Simple Type Specification
    IO.puts("\n\n4️⃣ Simple Type Specification Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    simple_model = %{
      product_name: :string,
      price: :float,
      in_stock: :boolean,
      categories: {:array, :string},
      rating: :float
    }
    
    product_messages = [
      %{
        role: "user",
        content: """
        Extract product info:
        The new MacBook Pro M3 is available for $1999. It's currently in stock.
        Categories: Computers, Laptops, Apple Products. 
        Customer rating: 4.8 out of 5 stars.
        """
      }
    ]
    
    case ExLLM.chat(:anthropic, product_messages,
      response_model: simple_model,
      max_retries: 2
    ) do
      {:ok, product} ->
        IO.puts("Product: #{product.product_name}")
        IO.puts("Price: $#{product.price}")
        IO.puts("In Stock: #{product.in_stock}")
        IO.puts("Categories: #{Enum.join(product.categories, ", ")}")
        IO.puts("Rating: #{product.rating}/5.0")
        
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    
    IO.puts("\n\n✅ All examples completed!")
  end
end

# Run the examples
Examples.run()