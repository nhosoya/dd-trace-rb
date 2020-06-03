require 'spec_helper'

require 'ddtrace/profiling/events/stack'
require 'ddtrace/profiling/pprof/stack_sample'

RSpec.describe Datadog::Profiling::Pprof::StackSample do
  subject(:builder) { described_class.new(builder) }
  let(:stack_samples) { Array.new(2) { build_stack_sample } }

  def build_stack_sample(locations = nil, thread_id = nil, wall_time_ns = nil)
    locations ||= Thread.current.backtrace_locations

    Datadog::Profiling::Events::StackSample.new(
      nil,
      locations,
      locations.length,
      thread_id || rand(1e9),
      wall_time_ns || rand(1e9)
    )
  end

  def string_id_for(string)
    builder.string_table.fetch(string)
  end

  describe '#to_profile' do
    subject(:to_profile) { builder.to_profile }
    it { is_expected.to be_kind_of(Perftools::Profiles::Profile) }

    context 'called twice' do
      it 'returns the same Profile instance' do
        is_expected.to eq(builder.to_profile)
      end
    end
  end

  describe '#build_profile' do
    subject(:build_profile) { builder.build_profile(stack_samples) }

    context 'builds a Profile' do
      it do
        is_expected.to be_kind_of(Perftools::Profiles::Profile)
        is_expected.to have_attributes(
          sample_type: array_including(kind_of(Perftools::Profiles::ValueType)),
          sample: array_including(kind_of(Perftools::Profiles::Sample)),
          mapping: array_including(kind_of(Perftools::Profiles::Mapping)),
          location: array_including(kind_of(Perftools::Profiles::Location)),
          function: array_including(kind_of(Perftools::Profiles::Function)),
          string_table: array_including(kind_of(String))
        )
      end
    end
  end

  describe '#group_events' do
    subject(:group_events) { builder.group_events(stack_samples) }
    let(:stack_samples) { [first, second] }

    context 'given stack samples' do
      let(:thread_id) { 1 }
      let(:stack) { Thread.current.backtrace_locations }

      shared_examples_for 'independent stack samples' do
        it 'yields each stack sample with their values' do
          expect { |b| builder.group_events(stack_samples, &b) }
            .to yield_successive_args(
              [first, builder.build_sample_values(first)],
              [second, builder.build_sample_values(second)]
            )
        end
      end

      context 'with identical threads and stacks' do
        let(:first) { build_stack_sample(stack, 1) }
        let(:second) { build_stack_sample(stack, 1) }
        before { expect(first.frames).to eq(second.frames) }

        it 'yields only the first unique stack sample with combined values' do
          expect { |b| builder.group_events(stack_samples, &b) }
            .to yield_with_args(
              first,
              [first.wall_time_interval_ns + second.wall_time_interval_ns]
            )
        end
      end

      context 'with identical threads and different' do
        let(:thread_id) { 1 }

        context 'stacks' do
          let(:first) { build_stack_sample(nil, thread_id) }
          let(:second) { build_stack_sample(nil, thread_id) }
          before { expect(first.frames).to_not eq(second.frames) }

          it_behaves_like 'independent stack samples'
        end

        context 'stack lengths' do
          let(:first) do
            Datadog::Profiling::Events::StackSample.new(
              nil,
              stack,
              stack.length,
              thread_id,
              rand(1e9)
            )
          end

          let(:second) do
            Datadog::Profiling::Events::StackSample.new(
              nil,
              stack,
              stack.length + 1,
              thread_id,
              rand(1e9)
            )
          end

          before { expect(first.total_frame_count).to_not eq(second.total_frame_count) }

          it_behaves_like 'independent stack samples'
        end
      end

      context 'with identical stacks and different thread IDs' do
        let(:first) { build_stack_sample(stack, 1) }
        let(:second) { build_stack_sample(stack, 2) }

        before do
          expect(first.frames).to eq(second.frames)
          expect(first.thread_id).to_not eq(second.thread_id)
        end

        it_behaves_like 'independent stack samples'
      end
    end
  end

  describe '#event_group_key' do
    subject(:event_group_key) { builder.event_group_key(stack_sample) }
    let(:stack_sample) { build_stack_sample }

    it { is_expected.to be_kind_of(Integer) }

    context 'given stack samples' do
      let(:first_key) { builder.event_group_key(first) }
      let(:second_key) { builder.event_group_key(second) }

      let(:thread_id) { 1 }
      let(:stack) { Thread.current.backtrace_locations }

      context 'with identical threads and stacks' do
        let(:first) { build_stack_sample(stack, 1) }
        let(:second) { build_stack_sample(stack, 1) }
        before { expect(first.frames).to eq(second.frames) }
        it { expect(first_key).to eq(second_key) }
      end

      context 'with identical threads and different' do
        let(:thread_id) { 1 }

        context 'stacks' do
          let(:first) { build_stack_sample(nil, thread_id) }
          let(:second) { build_stack_sample(nil, thread_id) }
          before { expect(first.frames).to_not eq(second.frames) }
          it { expect(first_key).to_not eq(second_key) }
        end

        context 'stack lengths' do
          let(:first) do
            Datadog::Profiling::Events::StackSample.new(
              nil,
              stack,
              stack.length,
              thread_id,
              rand(1e9)
            )
          end

          let(:second) do
            Datadog::Profiling::Events::StackSample.new(
              nil,
              stack,
              stack.length + 1,
              thread_id,
              rand(1e9)
            )
          end

          before { expect(first.total_frame_count).to_not eq(second.total_frame_count) }
          it { expect(first_key).to_not eq(second_key) }
        end
      end

      context 'with identical stacks and different thread IDs' do
        let(:first) { build_stack_sample(stack, 1) }
        let(:second) { build_stack_sample(stack, 2) }

        before do
          expect(first.frames).to eq(second.frames)
          expect(first.thread_id).to_not eq(second.thread_id)
        end

        it { expect(first_key).to_not eq(second_key) }
      end
    end
  end

  describe '#build_sample_types' do
    subject(:build_sample_types) { builder.build_sample_types }

    it do
      is_expected.to be_kind_of(Array)
      is_expected.to have(1).items
    end

    describe 'produces a value type' do
      subject(:label) { build_sample_types.first }
      it { is_expected.to be_kind_of(Perftools::Profiles::ValueType) }
      it do
        is_expected.to have_attributes(
          type: string_id_for(described_class::VALUE_TYPE_WALL),
          unit: string_id_for(described_class::VALUE_UNIT_NANOSECONDS)
        )
      end
    end
  end

  describe '#build_sample' do
    subject(:build_sample) { builder.build_sample(stack_sample, values) }
    let(:stack_sample) { build_stack_sample }
    let(:values) { [stack_sample.wall_time_interval_ns] }

    context 'builds a Sample' do
      it do
        is_expected.to be_kind_of(Perftools::Profiles::Sample)
        is_expected.to have_attributes(
          location_id: array_including(kind_of(Integer)),
          value: values,
          label: array_including(kind_of(Perftools::Profiles::Label))
        )
      end

      context 'whose locations' do
        subject(:locations) { build_sample.location_id }
        it { is_expected.to have(stack_sample.frames.length).items }
        it 'each map to a Location on the profile' do
          locations.each do |id|
            expect(builder.locations.messages[id])
              .to be_kind_of(Perftools::Profiles::Location)
          end
        end
      end

      context 'whose labels' do
        subject(:locations) { build_sample.label }
        it { is_expected.to have(1).items }
      end
    end
  end

  describe '#build_sample_values' do
    subject(:build_sample_values) { builder.build_sample_values(stack_sample) }
    let(:stack_sample) { build_stack_sample }
    it { is_expected.to eq([stack_sample.wall_time_interval_ns]) }
  end

  describe '#build_sample_labels' do
    subject(:build_sample_labels) { builder.build_sample_labels(stack_sample) }
    let(:stack_sample) { build_stack_sample }

    it do
      is_expected.to be_kind_of(Array)
      is_expected.to have(1).items
    end

    describe 'produces a label' do
      subject(:label) { build_sample_labels.first }
      it { is_expected.to be_kind_of(Perftools::Profiles::Label) }
      it do
        is_expected.to have_attributes(
          key: string_id_for(described_class::LABEL_KEY_THREAD_ID),
          str: string_id_for(stack_sample.thread_id.to_s)
        )
      end
    end
  end
end
